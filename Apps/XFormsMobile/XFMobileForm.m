/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFMobileForm.h"
#import <XFormsKit/XFormsKit.h>

@interface XFMobileForm ()
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, assign) BOOL holdsAccess;
@end

@implementation XFMobileForm

+ (instancetype)formWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    if (url == nil) {
        return nil;
    }
    XFMobileForm *form = [[XFMobileForm alloc] init];
    form.url = url;
    form.holdsAccess = [url startAccessingSecurityScopedResource];

    NSError *readError = nil;
    NSString *xml = [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:&readError];
    if (xml == nil) {
        // not every form is UTF-8; let the system sniff before giving up
        xml = [NSString stringWithContentsOfURL:url usedEncoding:NULL error:NULL];
    }
    if (xml == nil) {
        if (error) { *error = readError; }
        return nil;
    }
    NSError *loadError = nil;
    // the base URL rides in with the source: relative instance/@src,
    // includes and schemas are resolved DURING construction
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml
                                                        baseURL:url
                                                          error:&loadError];
    if (processor == nil) {
        if (error) { *error = loadError; }
        return nil;
    }
    form.processor = processor;
    return form;
}

- (NSString *)title
{
    NSString *name = [[self.url lastPathComponent] stringByDeletingPathExtension];
    return name.length ? name : NSLocalizedString(@"Form", nil);
}

- (void)dealloc
{
    [_processor close];   // xforms-model-destruct listeners (G-54)
    if (_holdsAccess) {
        [_url stopAccessingSecurityScopedResource];
    }
}

@end
