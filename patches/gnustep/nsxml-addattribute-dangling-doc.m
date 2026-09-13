/* GNUstep: -[NSXMLElement addAttribute:] leaves the value nodes of a
 * prefixed attribute pointing at a document it has just freed.
 *
 * Foundation only -- no XFormsKit. Build an element with a prefixed
 * attribute whose prefix is not declared yet (the shape every XFormsKit
 * authoring edit produces: an xf:* element with an ev:event attribute,
 * built detached and then inserted into the host document), insert it,
 * and look at where its pieces think they live.
 *
 *   clang -o nsxml-addattribute-dangling-doc nsxml-addattribute-dangling-doc.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 *   ./nsxml-addattribute-dangling-doc          # exit 1: the value node dangles
 *   valgrind ./nsxml-addattribute-dangling-doc  # "Invalid read ... free'd by xmlFreeDoc
 *                                               #  ... in -[NSXMLElement addAttribute:]"
 *
 * What happens. -[NSXMLNode setName:] with a prefix that resolves to
 * nothing makes a placeholder xmlNs (prefix set, href NULL) and gives the
 * attribute a private xmlDoc to hold it. -[NSXMLElement addAttribute:] then
 * asks libxml2 to move the attribute into the element's document with
 * xmlDOMWrapAdoptNode(). xmlDOMWrapAdoptAttr() rejects a namespace without
 * an href -- but only after it has set attr->doc and before it walks the
 * attribute's value nodes -- and returns -1. addAttribute: ignores the
 * result and frees the private document. The attribute's text node still
 * points at it.
 *
 * The next thing that walks the attribute reads that freed memory:
 * -[NSXMLNode detach] (setTreeDoc -> adoptString -> xmlDictOwns on the
 * stale doc's dictionary), or the element's dealloc. Whether that is a
 * segfault or silence depends on what the allocator has since put in the
 * chunk, which is why the XFormsKit suite dies in testActionAuthoring on
 * one machine and passes on another.
 *
 * libxml2 2.12+ hides it: gnustep-base's -[NSXMLNode _insertChild:atIndex:]
 * uses its own updateTreeDocManually() there, which rewrites every doc
 * pointer under the element unconditionally and so repairs the attribute
 * by accident when the element is inserted. On 2.9.x (Ubuntu 24.04) the
 * same path uses xmlDOMWrapAdoptNode(), whose "paranoid source-doc check"
 * skips any node whose doc is not the source doc -- exactly the dangling
 * one -- and the crash follows.
 *
 * The accompanying patch, gnustep-base-nsxmlelement-addattribute-value-doc.patch,
 * checks the result of xmlDOMWrapAdoptNode() and, when it fails, moves the
 * attribute subtree with xmlSetTreeDoc() before the private document is
 * freed. With it this program exits 0, valgrind is clean, and
 * gnustep-base's own NSXML suites (524 tests) are unaffected.
 */
#import <Foundation/Foundation.h>
#include <libxml/tree.h>

@interface NSXMLNode (GSPrivateProbe)
- (void *) _node;   /* gnustep-base private: the libxml2 node behind the wrapper */
@end

/* Where each piece of the element believes it lives. */
static int dump(const char *tag, NSXMLElement *el)
{
  xmlNodePtr n = (xmlNodePtr)[el _node];
  xmlAttrPtr a;
  int dangling = 0;

  printf("%s: element doc=%p", tag, (void *)n->doc);
  for (a = n->properties; a != NULL; a = a->next)
    {
      xmlDocPtr valueDoc = a->children ? a->children->doc : NULL;

      printf(" | @%s doc=%p value-doc=%p", (const char *)a->name,
        (void *)a->doc, (void *)valueDoc);
      if (a->children != NULL && valueDoc != n->doc)
        {
          dangling = 1;
        }
    }
  printf("%s\n", dangling ? "   <-- value node points elsewhere" : "");
  fflush(stdout);
  return dangling;
}

int main(int argc, char **argv)
{
  int dangling;

  @autoreleasepool
    {
      NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<body><xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger></body></html>";
      NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString: xml
                                                            options: 0
                                                              error: NULL];
      NSXMLElement *body = (NSXMLElement *)[[doc rootElement] childAtIndex: 0];
      NSXMLElement *trigger = (NSXMLElement *)[body childAtIndex: 0];

      /* Built detached, as an editor does, then placed. */
      NSXMLElement *el = [NSXMLElement elementWithName: @"xf:message"];
      [el addAttribute: [NSXMLNode attributeWithName: @"id" stringValue: @"message1"]];
      [el addAttribute: [NSXMLNode attributeWithName: @"ev:event" stringValue: @"DOMActivate"]];
      dangling = dump("after addAttribute", el);
      [trigger insertChild: el atIndex: [trigger childCount]];
      /* A gnustep-base built against libxml2 2.12+ repairs the pointer here
       * as a side effect (see above); one built against 2.9.x does not. */
      dangling |= dump("after insertChild ", el);

      /* Serialising is fine either way; the stale pointer is only read when
       * the attribute's subtree is moved again.  Under valgrind this is the
       * invalid read; on a bare run it is a segfault or nothing, depending
       * on what now occupies the freed chunk. */
      printf("%s\n", [[el XMLString] UTF8String]);
      [el detach];
      [doc release];
    }
  printf(dangling ? "FAIL: a value node still points at the document addAttribute: freed\n"
                  : "ok: every value node follows its element\n");
  return dangling;
}
