#import "XFHostEdit.h"
#import "XFProcessor.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFAbstractAction.h"

/// Controls that carry an xf:label child when inserted.
static NSSet *XFLabeledControls(void)
{
    static NSSet *set;
    if (set == nil) {
        set = [NSSet setWithArray:@[ @"input", @"output", @"secret", @"textarea",
            @"select", @"select1", @"range", @"trigger", @"submit", @"upload",
            @"group", @"dialog" ]];
    }
    return set;
}

static NSArray *XFUIControlNames(void)
{
    return @[ @"input", @"output", @"secret", @"textarea", @"select1", @"select",
              @"range", @"trigger", @"submit", @"upload",
              @"group", @"repeat", @"switch", @"dialog" ];
}

/// The action elements the palette offers, in palette order: the XForms
/// 1.1 action module (§10) plus the XSLTForms dialog pair the engine
/// implements (show / hide).
static NSArray *XFActionNames(void)
{
    return @[ @"action", @"setvalue", @"insert", @"delete", @"toggle",
              @"setindex", @"setfocus", @"send", @"dispatch", @"load",
              @"message", @"reset",
              @"rebuild", @"recalculate", @"revalidate", @"refresh",
              @"show", @"hide" ];
}

@implementation XFHostEdit

+ (instancetype)editWithProcessor:(XFProcessor *)processor
                      undoManager:(NSUndoManager *)undoManager
{
    XFHostEdit *e = [[self alloc] init];
    e->_processor = processor;
    e.undoManager = undoManager;
    return e;
}

- (void)noteChanged:(XFXMLElement *)element
{
    if (self.changedHandler) {
        self.changedHandler(element);
    }
}

#pragma mark - Identifiers

- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix
{
    NSMutableSet *taken = [NSMutableSet set];
    XFXMLElement *root = [self.processor.hostDocument rootElement];
    NSMutableArray *queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    while (queue.count) {
        XFXMLElement *e = [queue lastObject];
        [queue removeLastObject];
        NSString *identifier = [[e attributeForName:@"id"] stringValue];
        if (identifier.length) {
            [taken addObject:identifier];
        }
        for (XFXMLNode *c in [e children]) {
            if ([c kind] == XFXMLElementKind) {
                [queue addObject:(XFXMLElement *)c];
            }
        }
    }
    NSUInteger n = 1;
    NSString *candidate;
    do {
        candidate = [NSString stringWithFormat:@"%@-%lu", prefix, (unsigned long)n++];
    } while ([taken containsObject:candidate]);
    return candidate;
}

#pragma mark - Insertion zones

+ (NSArray<NSString *> *)insertableNamesUnderParent:(XFXMLElement *)parent
{
    if (parent == nil) {
        return @[];
    }
    NSString *local = [parent localName];
    BOOL xforms = [XFXML element:parent hasLocalName:local namespaceURI:XFXFormsNamespaceURI];
    if (xforms) {
        // event handlers (the action module) hang off nearly everything:
        // controls (DOMActivate, value-changed), containers, models
        // (xforms-ready), submissions (xforms-submit-done), and nest
        // inside xf:action
        if ([local isEqualToString:@"model"]) {
            return [@[ @"instance", @"bind", @"submission" ]
                       arrayByAddingObjectsFromArray:XFActionNames()];
        }
        if ([local isEqualToString:@"submission"]) {
            return XFActionNames();
        }
        if ([local isEqualToString:@"switch"]) {
            return [@[ @"case" ] arrayByAddingObjectsFromArray:XFActionNames()];
        }
        if ([local isEqualToString:@"select"] || [local isEqualToString:@"select1"]) {
            return [@[ @"item", @"itemset" ] arrayByAddingObjectsFromArray:XFActionNames()];
        }
        if ([local isEqualToString:@"group"] || [local isEqualToString:@"case"]
            || [local isEqualToString:@"repeat"] || [local isEqualToString:@"dialog"]) {
            return [XFUIControlNames() arrayByAddingObjectsFromArray:XFActionNames()];
        }
        if ([local isEqualToString:@"action"]) {
            return XFActionNames();
        }
        if ([XFUIControlNames() containsObject:local]) {
            return XFActionNames();
        }
        // instance data, binds, support children: nothing from the palette
        return @[];
    }
    // host markup: the head gets a model; body-side containers get controls
    if ([local isEqualToString:@"head"]) {
        return @[ @"model" ];
    }
    static NSSet *containers;
    if (containers == nil) {
        containers = [NSSet setWithArray:@[ @"body", @"div", @"p", @"td", @"th",
            @"li", @"fieldset", @"section", @"article", @"blockquote", @"span" ]];
    }
    if ([containers containsObject:local]) {
        // refuse anywhere outside the body's subtree (e.g. head/title)
        XFXMLNode *walk = parent;
        while (walk) {
            if ([walk kind] == XFXMLElementKind
                && [[(XFXMLElement *)walk localName] isEqualToString:@"body"]) {
                return XFUIControlNames();
            }
            walk = [walk parent];
        }
        return @[];
    }
    return @[];
}

+ (BOOL)canInsertElementNamed:(NSString *)localName underParent:(XFXMLElement *)parent
{
    return [[self insertableNamesUnderParent:parent] containsObject:localName];
}

#pragma mark - Element creation

/// The document's prefix for the XForms namespace ("xf" declared on the
/// root when the document has none).
- (NSString *)xformsPrefix
{
    XFXMLElement *root = [self.processor.hostDocument rootElement];
    for (XFXMLNode *ns in [root namespaces]) {
        if ([[ns stringValue] isEqualToString:XFXFormsNamespaceURI] && [ns name].length) {
            return [ns name];
        }
    }
    // no prefixed declaration: declare xf: on the root
    XFXMLNode *decl = [XFXMLNode namespaceWithName:@"xf" stringValue:XFXFormsNamespaceURI];
    [root addNamespace:(XFXMLNode *)decl];
    return @"xf";
}

- (XFXMLElement *)makeXFormsElement:(NSString *)localName
{
    return [XFXMLElement elementWithName:
        [NSString stringWithFormat:@"%@:%@", [self xformsPrefix], localName]];
}

/// The document's prefix for the XML Events namespace ("ev" declared on
/// the root when the document has none) — ev:event and friends.
- (NSString *)eventsPrefix
{
    XFXMLElement *root = [self.processor.hostDocument rootElement];
    for (XFXMLNode *ns in [root namespaces]) {
        if ([[ns stringValue] isEqualToString:XFXMLEventsNamespaceURI] && [ns name].length) {
            return [ns name];
        }
    }
    XFXMLNode *decl = [XFXMLNode namespaceWithName:@"ev" stringValue:XFXMLEventsNamespaceURI];
    [root addNamespace:(XFXMLNode *)decl];
    return @"ev";
}

- (XFXMLElement *)insertElementNamed:(NSString *)localName
                         underParent:(XFXMLElement *)parent
                             atIndex:(NSInteger)index
                               error:(NSError **)error
{
    if (![[self class] canInsertElementNamed:localName underParent:parent]) {
        if (error) {
            *error = [NSError errorWithDomain:@"XFormsKit" code:1 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"%@ cannot be inserted under %@", localName, [parent localName] ?: @"?"] }];
        }
        return nil;
    }
    XFXMLElement *element = [self makeXFormsElement:localName];
    [element addAttribute:[XFXMLNode attributeWithName:@"id"
        stringValue:[self uniqueIdentifierWithPrefix:localName]]];
    if ([XFLabeledControls() containsObject:localName]) {
        XFXMLElement *label = [self makeXFormsElement:@"label"];
        [label setStringValue:[[[localName substringToIndex:1] uppercaseString]
            stringByAppendingString:[localName substringFromIndex:1]]];
        [element addChild:label];
    }
    if ([localName isEqualToString:@"item"]) {
        XFXMLElement *label = [self makeXFormsElement:@"label"];
        [label setStringValue:@"Item"];
        XFXMLElement *value = [self makeXFormsElement:@"value"];
        [value setStringValue:@"item"];
        [element addChild:label];
        [element addChild:value];
    }
    if ([localName isEqualToString:@"instance"]) {
        // a starter data document, so binds and refs have something to hit
        XFXMLElement *data = [XFXMLElement elementWithName:@"data"];
        [data addNamespace:[XFXMLNode namespaceWithName:@"" stringValue:@""]];
        [element addChild:data];
    }
    if ([localName isEqualToString:@"itemset"]) {
        // a compilable starter: nodeset plus per-node label / value refs
        [element addAttribute:[XFXMLNode attributeWithName:@"nodeset" stringValue:@"."]];
        XFXMLElement *label = [self makeXFormsElement:@"label"];
        [label addAttribute:[XFXMLNode attributeWithName:@"ref" stringValue:@"."]];
        XFXMLElement *value = [self makeXFormsElement:@"value"];
        [value addAttribute:[XFXMLNode attributeWithName:@"ref" stringValue:@"."]];
        [element addChild:label];
        [element addChild:value];
    }
    if ([XFActionNames() containsObject:localName]
        && ![XFAbstractAction isActionElement:parent]) {
        // a handler without ev:event never fires — start with the event
        // its position suggests (nested actions inherit the outer one)
        NSString *parentLocal = [parent localName];
        NSString *event = @"DOMActivate";
        if ([parentLocal isEqualToString:@"model"]) {
            event = @"xforms-ready";
        } else if ([parentLocal isEqualToString:@"submission"]) {
            event = @"xforms-submit-done";
        }
        [element addAttribute:[XFXMLNode attributeWithName:
            [NSString stringWithFormat:@"%@:event", [self eventsPrefix]]
                                                stringValue:event]];
    }
    [self reinsertElement:element underParent:parent atIndex:index];
    return element;
}

/// Physical insert + processor attach + inverse registration. Also the
/// undo of deleteElement:, so the SAME element object returns.
- (void)reinsertElement:(XFXMLElement *)element
            underParent:(XFXMLElement *)parent
                atIndex:(NSInteger)index
{
    NSUInteger count = [parent childCount];
    NSUInteger at = (index < 0 || (NSUInteger)index > count) ? count : (NSUInteger)index;
    [parent insertChild:element atIndex:at];
    [self.processor attachElement:element error:NULL];
    [[self.undoManager prepareWithInvocationTarget:self] deleteElement:element];
    [self.undoManager setActionName:@"Insert Element"];
    [self noteChanged:element];
}

- (BOOL)moveElement:(XFXMLElement *)element
        underParent:(XFXMLElement *)parent
            atIndex:(NSInteger)index
{
    XFXMLElement *oldParent = (XFXMLElement *)[element parent];
    if (element == nil || parent == nil || [oldParent kind] != XFXMLElementKind) {
        return NO;
    }
    // never into itself or its own subtree
    for (XFXMLNode *walk = parent; walk != nil; walk = [walk parent]) {
        if (walk == element) {
            return NO;
        }
    }
    // the zone table speaks XForms; SVG shapes reorder freely among SVG
    // parents (paint order is the designer's concern there)
    NSString *svgNS = @"http://www.w3.org/2000/svg";
    BOOL svgMove = [[element URI] isEqualToString:svgNS]
        && [[parent URI] isEqualToString:svgNS];
    if (!svgMove
        && ![XFHostEdit canInsertElementNamed:[element localName] underParent:parent]) {
        return NO;
    }
    NSInteger oldIndex = (NSInteger)[element index];
    NSInteger newIndex = index;
    if (parent == oldParent) {
        // the index is against the tree BEFORE the move; the detach below
        // shifts everything after the old slot left by one
        NSInteger count = (NSInteger)[parent childCount];
        NSInteger resolved = (newIndex < 0 || newIndex > count) ? count : newIndex;
        if (resolved == oldIndex || resolved == oldIndex + 1) {
            return NO;   // dropping right where it already is
        }
        if (resolved > oldIndex) {
            newIndex = resolved - 1;
        } else {
            newIndex = resolved;
        }
    }
    // same order as deleteElement: physical removal first, so the
    // processor's rebuild does not re-instantiate the element in place
    [element detach];
    [self.processor detachElement:element];
    if ([XFAbstractAction isActionElement:oldParent]) {
        [self.processor noteElementChanged:oldParent];
    }
    NSUInteger count = [parent childCount];
    NSUInteger at = (newIndex < 0 || (NSUInteger)newIndex > count) ? count : (NSUInteger)newIndex;
    [parent insertChild:element atIndex:at];
    [self.processor attachElement:element error:NULL];
    // the inverse is a move back; for a same-parent move its index must
    // read correctly against the POST-move tree the undo will see (the
    // undo re-applies the same before-the-move interpretation)
    NSInteger backIndex = oldIndex;
    if (parent == oldParent && oldIndex > (NSInteger)at) {
        backIndex = oldIndex + 1;
    }
    [[self.undoManager prepareWithInvocationTarget:self]
        moveElement:element underParent:oldParent atIndex:backIndex];
    [self.undoManager setActionName:@"Move Element"];
    [self noteChanged:element];
    return YES;
}

- (void)deleteElement:(XFXMLElement *)element
{
    XFXMLElement *parent = (XFXMLElement *)[element parent];
    if ([parent kind] != XFXMLElementKind) {
        return;   // never delete the root
    }
    NSInteger index = (NSInteger)[element index];
    // physical removal FIRST: detachElement rebuilds the host nodes, and a
    // still-present element would be re-instantiated on the spot
    [element detach];
    [self.processor detachElement:element];
    if ([XFAbstractAction isActionElement:parent]) {
        // a nested action left a compound handler — recompile it
        [self.processor noteElementChanged:parent];
    }
    [[self.undoManager prepareWithInvocationTarget:self]
        reinsertElement:element underParent:parent atIndex:index];
    [self.undoManager setActionName:@"Delete Element"];
    [self noteChanged:parent];
}

#pragma mark - Attributes

- (void)setAttribute:(NSString *)name value:(NSString *)value onElement:(XFXMLElement *)element
{
    if ([name hasPrefix:@"ev:"]) {
        // callers say "ev:" conventionally; land on the prefix the
        // document actually declares (declaring ev on the root if new)
        name = [NSString stringWithFormat:@"%@:%@",
                [self eventsPrefix], [name substringFromIndex:3]];
    }
    NSString *old = [[element attributeForName:name] stringValue];
    if ((old ?: @"").length == 0 && value.length == 0) {
        return;
    }
    if ([old isEqualToString:value ?: @""]) {
        return;
    }
    if (value.length) {
        [element removeAttributeForName:name];
        [element addAttribute:[XFXMLNode attributeWithName:name stringValue:value]];
    } else {
        [element removeAttributeForName:name];
    }
    [self.processor noteElementChanged:element];
    [[self.undoManager prepareWithInvocationTarget:self]
        setAttribute:name value:old ?: @"" onElement:element];
    [self.undoManager setActionName:@"Change Attribute"];
    [self noteChanged:element];
}

#pragma mark - Support children (label / hint / help / alert)

- (NSString *)supportChildText:(NSString *)localName onElement:(XFXMLElement *)element
{
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    return child ? [XFXML stringValueOfNode:child] : nil;
}

- (void)setSupportChild:(NSString *)localName text:(NSString *)text onElement:(XFXMLElement *)element
{
    NSString *old = [self supportChildText:localName onElement:element];
    if ([old ?: @"" isEqualToString:text ?: @""]) {
        return;
    }
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    if (text.length == 0) {
        [child detach];
    } else if (child) {
        // keep the child element, replace its content with plain text
        for (XFXMLNode *c in [[child children] copy]) {
            [c detach];
        }
        [child setStringValue:text];
    } else {
        child = [self makeXFormsElement:localName];
        [child setStringValue:text];
        // labels lead; the other support children follow the content
        if ([localName isEqualToString:@"label"]) {
            [element insertChild:child atIndex:0];
        } else {
            [element addChild:child];
        }
    }
    [self.processor noteElementChanged:element];
    [[self.undoManager prepareWithInvocationTarget:self]
        setSupportChild:localName text:old ?: @"" onElement:element];
    [self.undoManager setActionName:@"Change Text"];
    [self noteChanged:element];
}

/// The URI `prefix` resolves to on `start`'s ancestor chain (start
/// exclusive is the caller's business — pass the parent to ignore a local
/// declaration). Hand-rolled: resolveNamespaceForName: differs across
/// platforms for the default namespace.
static NSString *XFResolveNSURI(XFXMLNode *start, NSString *prefix)
{
    for (XFXMLNode *n = start; n != nil; n = [n parent]) {
        if ([n kind] != XFXMLElementKind) {
            continue;
        }
        for (XFXMLNode *ns in [(XFXMLElement *)n namespaces]) {
            if ([([ns name] ?: @"") isEqualToString:prefix]) {
                return [ns stringValue] ?: @"";
            }
        }
    }
    return nil;
}

/// Deep clone that rebuilds elements as fresh nodes named by string —
/// -copy pins the resolved namespace declarations onto the copy (GNUstep
/// then serializes `<strong xmlns="…">` inside every label, and stripping
/// the pinned declaration afterwards loses the element's prefix), so the
/// clone drops that baggage instead: XForms-namespace elements get the
/// document's prefix (whatever prefix the fragment used), XHTML and
/// no-namespace inline markup stays unprefixed and inherits the host
/// default, and a foreign-namespace element keeps its name with its
/// declaration attached locally.
static XFXMLNode *XFCleanCloneNode(XFXMLNode *node, NSString *xfPrefix)
{
    if ([node kind] != XFXMLElementKind) {
        return [node copy];
    }
    XFXMLElement *src = (XFXMLElement *)node;
    NSString *uri = [src URI] ?: XFResolveNSURI(src, [src prefix] ?: @"") ?: @"";
    XFXMLElement *dst;
    if ([uri isEqualToString:XFXFormsNamespaceURI]) {
        dst = [XFXMLElement elementWithName:
            [NSString stringWithFormat:@"%@:%@", xfPrefix, [src localName]]];
    } else if (uri.length == 0 || [uri isEqualToString:XFXHTMLNamespaceURI]) {
        dst = [XFXMLElement elementWithName:[src localName]];
    } else {
        dst = [XFXMLElement elementWithName:[src name]];
        [dst addNamespace:[XFXMLNode namespaceWithName:[src prefix] ?: @"" stringValue:uri]];
    }
    for (XFXMLNode *attr in [src attributes]) {
        [dst addAttribute:[XFXMLNode attributeWithName:[attr name]
                                           stringValue:[attr stringValue] ?: @""]];
    }
    for (XFXMLNode *c in [src children]) {
        [dst addChild:XFCleanCloneNode(c, xfPrefix)];
    }
    return dst;
}

- (NSString *)supportChildXML:(NSString *)localName onElement:(XFXMLElement *)element
{
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    if (child == nil) {
        return nil;
    }
    // seam-free join: this is mixed inline content, where an inserted
    // newline would become label text (contentXMLOfElement's "\n" join is
    // for the block-shaped instance editor)
    NSMutableString *out = [NSMutableString string];
    for (XFXMLNode *c in [child children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

- (BOOL)setSupportChild:(NSString *)localName
             contentXML:(NSString *)xml
              onElement:(XFXMLElement *)element
                  error:(NSError **)error
{
    NSString *old = [self supportChildXML:localName onElement:element];
    if ([old ?: @"" isEqualToString:xml ?: @""]) {
        return YES;
    }
    NSArray *nodes = nil;
    if (xml.length) {
        nodes = [self cleanNodesFromFragment:xml error:error];
        if (nodes == nil) {
            return NO;
        }
    }
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    if (xml.length == 0) {
        [child detach];
    } else {
        if (child == nil) {
            child = [self makeXFormsElement:localName];
            // labels lead; the other support children follow the content
            if ([localName isEqualToString:@"label"]) {
                [element insertChild:child atIndex:0];
            } else {
                [element addChild:child];
            }
        } else {
            for (XFXMLNode *c in [[child children] copy]) {
                [c detach];
            }
        }
        for (XFXMLNode *c in nodes) {
            [child addChild:c];
        }
    }
    [self.processor noteElementChanged:element];
    [[self.undoManager prepareWithInvocationTarget:self]
        setSupportChild:localName contentXML:old onElement:element error:NULL];
    [self.undoManager setActionName:@"Change Text"];
    [self noteChanged:element];
    return YES;
}

- (NSString *)supportChildAttribute:(NSString *)attribute
                              child:(NSString *)localName
                          onElement:(XFXMLElement *)element
{
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    return child ? [[child attributeForName:attribute] stringValue] : nil;
}

- (void)setSupportChildAttribute:(NSString *)attribute
                           child:(NSString *)localName
                           value:(NSString *)value
                       onElement:(XFXMLElement *)element
{
    NSString *old = [self supportChildAttribute:attribute child:localName onElement:element];
    if ([old ?: @"" isEqualToString:value ?: @""]) {
        return;
    }
    XFXMLElement *child = [XFXML childElementWithLocalName:localName
                                              namespaceURI:XFXFormsNamespaceURI
                                                 ofElement:element];
    if (child == nil) {
        if (value.length == 0) {
            return;
        }
        child = [self makeXFormsElement:localName];
        if ([localName isEqualToString:@"label"]) {
            [element insertChild:child atIndex:0];
        } else {
            [element addChild:child];
        }
    }
    [child removeAttributeForName:attribute];
    if (value.length) {
        [child addAttribute:[XFXMLNode attributeWithName:attribute stringValue:value]];
    }
    [self.processor noteElementChanged:element];
    [[self.undoManager prepareWithInvocationTarget:self]
        setSupportChildAttribute:attribute child:localName value:old ?: @"" onElement:element];
    [self.undoManager setActionName:@"Change Attribute"];
    [self noteChanged:element];
}

/// Parses `xml` as inline mixed content — the label vocabulary: host
/// inline markup (default namespace) plus xf:output / itext, with the
/// document's XForms prefix and the conventional xf: bound — and returns
/// clean clones ready to insert. nil (with `error`) when it does not
/// parse.
- (NSArray<XFXMLNode *> *)cleanNodesFromFragment:(NSString *)xml error:(NSError **)error
{
    NSString *prefix = [self xformsPrefix];
    NSMutableString *decls = [NSMutableString stringWithFormat:
        @" xmlns=\"%@\" xmlns:%@=\"%@\"", XFXHTMLNamespaceURI, prefix, XFXFormsNamespaceURI];
    if (![prefix isEqualToString:@"xf"]) {
        [decls appendFormat:@" xmlns:xf=\"%@\"", XFXFormsNamespaceURI];
    }
    NSString *wrapped = [NSString stringWithFormat:@"<xfd-wrap%@>%@</xfd-wrap>", decls, xml ?: @""];
    NSError *inner = nil;
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:wrapped options:0 error:&inner];
    if (doc == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:@"XFormsKit" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"The XML does not parse." }];
        }
        return nil;
    }
    NSMutableArray *nodes = [NSMutableArray array];
    for (XFXMLNode *c in [[doc rootElement] children]) {
        [nodes addObject:XFCleanCloneNode(c, prefix)];
    }
    return nodes;
}

- (NSString *)inlineContentXMLOfElement:(XFXMLElement *)element
{
    // seam-free join — mixed inline content, same as supportChildXML:
    NSMutableString *out = [NSMutableString string];
    for (XFXMLNode *c in [element children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

- (BOOL)setInlineContentXML:(NSString *)xml
                  onElement:(XFXMLElement *)element
                      error:(NSError **)error
{
    NSString *old = [self inlineContentXMLOfElement:element];
    if ([old isEqualToString:xml ?: @""]) {
        return YES;
    }
    NSArray *nodes = @[];
    if (xml.length) {
        nodes = [self cleanNodesFromFragment:xml error:error];
        if (nodes == nil) {
            return NO;
        }
    }
    for (XFXMLNode *c in [[element children] copy]) {
        [c detach];
    }
    for (XFXMLNode *c in nodes) {
        [element addChild:c];
    }
    [self.processor noteElementChanged:element];
    [[self.undoManager prepareWithInvocationTarget:self]
        setInlineContentXML:old onElement:element error:NULL];
    [self.undoManager setActionName:@"Edit Content"];
    [self noteChanged:element];
    return YES;
}

#pragma mark - Content replacement (the instance-data editor)

- (NSString *)contentXMLOfElement:(XFXMLElement *)element
{
    NSMutableArray *parts = [NSMutableArray array];
    for (XFXMLNode *child in [element children]) {
        [parts addObject:[child XMLString] ?: @""];
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (BOOL)setContentXML:(NSString *)xml onElement:(XFXMLElement *)element error:(NSError **)error
{
    NSString *wrapped = [NSString stringWithFormat:@"<xfd-wrap>%@</xfd-wrap>", xml ?: @""];
    NSError *inner = nil;
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:wrapped options:0 error:&inner];
    if (doc == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:@"XFormsKit" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"The XML does not parse." }];
        }
        return NO;
    }
    NSString *old = [self contentXMLOfElement:element];
    NSString *local = [element localName];
    BOOL adopted = [local isEqualToString:@"bind"] || [local isEqualToString:@"submission"];
    BOOL isInstance = [local isEqualToString:@"instance"];
    if (adopted) {
        [self.processor detachElement:element];
    }
    for (XFXMLNode *child in [[element children] copy]) {
        [child detach];
    }
    for (XFXMLNode *child in [[doc rootElement] children]) {
        // standalone copies — Apple's insertChild:atIndex: loses the content
        // of nodes detached from another document
        [element addChild:[child copy]];
    }
    if (isInstance) {
        // dropElement never removes a model's LAST instance, so detach +
        // re-attach would duplicate it: rebuild the existing XFInstance in
        // place instead
        XFModel *model = nil;
        XFInstance *instance = nil;
        for (XFModel *candidate in self.processor.models) {
            for (XFInstance *inst in candidate.instances) {
                if (inst.element == element) {
                    model = candidate;
                    instance = inst;
                    break;
                }
            }
        }
        [instance reloadInlineDocument];
        XFModel *target = model ?: self.processor.model;
        [target setRebuilded:YES];
        [target rebuild];
        [target refresh];
        [self.processor refreshControls];
    } else if (adopted) {
        [self.processor attachElement:element error:NULL];
    } else {
        [self.processor noteElementChanged:element];
    }
    [[self.undoManager prepareWithInvocationTarget:self]
        setContentXML:old onElement:element error:NULL];
    [self.undoManager setActionName:@"Edit Content"];
    [self noteChanged:element];
    return YES;
}

#pragma mark - XPath step building

/// One child step for `node` under its parent: the node's name, plus a
/// positional predicate when same-named siblings would make the bare name
/// ambiguous.
static NSString *XFStepForNode(XFXMLNode *node)
{
    if ([node kind] == XFXMLAttributeKind) {
        return [@"@" stringByAppendingString:[node name] ?: @""];
    }
    NSString *name = [node name] ?: [node localName] ?: @"*";
    XFXMLNode *parent = [node parent];
    if (parent == nil) {
        return name;
    }
    NSUInteger same = 0, position = 0;
    for (XFXMLNode *sibling in [parent children]) {
        if ([sibling kind] != XFXMLElementKind) {
            continue;
        }
        NSString *siblingName = [sibling name] ?: [sibling localName];
        if ([siblingName isEqualToString:name]) {
            same++;
            if (sibling == node) {
                position = same;
            }
        }
    }
    return same > 1 ? [NSString stringWithFormat:@"%@[%lu]", name, (unsigned long)position]
                    : name;
}

static NSArray *XFAncestryOf(XFXMLNode *node)
{
    NSMutableArray *chain = [NSMutableArray array];
    for (XFXMLNode *walk = node; walk != nil; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind || [walk kind] == XFXMLAttributeKind) {
            [chain insertObject:walk atIndex:0];
        } else if ([walk kind] == XFXMLDocumentKind) {
            [chain insertObject:walk atIndex:0];
        }
    }
    return chain;
}

+ (NSString *)pathFromNode:(XFXMLNode *)context toNode:(XFXMLNode *)target
{
    if (context == nil || target == nil) {
        return nil;
    }
    if (context == target) {
        return @".";
    }
    NSArray *up = XFAncestryOf(context);
    NSArray *down = XFAncestryOf(target);
    if (up.count == 0 || down.count == 0 || up[0] != down[0]) {
        return nil;   // different documents (or detached trees)
    }
    NSUInteger common = 0;
    while (common < up.count && common < down.count && up[common] == down[common]) {
        common++;
    }
    NSMutableArray *steps = [NSMutableArray array];
    for (NSUInteger i = common; i < up.count; i++) {
        [steps addObject:@".."];
    }
    for (NSUInteger i = common; i < down.count; i++) {
        [steps addObject:XFStepForNode(down[i])];
    }
    return steps.count ? [steps componentsJoinedByString:@"/"] : @".";
}

+ (NSString *)stepsBelowRootToNode:(XFXMLNode *)target
{
    if (target == nil) {
        return nil;
    }
    NSArray *chain = XFAncestryOf(target);
    // chain: [document?, documentElement, ...steps...]
    NSUInteger start = 0;
    while (start < chain.count && [(XFXMLNode *)chain[start] kind] == XFXMLDocumentKind) {
        start++;
    }
    if (start >= chain.count) {
        return nil;
    }
    NSMutableArray *steps = [NSMutableArray array];
    for (NSUInteger i = start + 1; i < chain.count; i++) {   // skip the document element
        [steps addObject:XFStepForNode(chain[i])];
    }
    return steps.count ? [steps componentsJoinedByString:@"/"] : @"";
}

@end
