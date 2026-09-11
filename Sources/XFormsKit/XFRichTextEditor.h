#import <AppKit/AppKit.h>

/// A minimal rich text editor for the XFRichText XHTML subset: a toolbar
/// (block popup + B I U S) over an NSTextView. `setHTML:` / `HTML` are the
/// storage interface — the text view holds the attributed form, XFRichText
/// converts both ways. No WebKit anywhere, so it behaves identically on
/// Apple AppKit and GNUstep. Used by the rich `xf:textarea` /
/// `xf:output mediatype="application/xhtml+xml"` widgets and by the
/// designer's label / hint / help / alert editors (XForms 1.1 allows
/// inline markup in those).
@interface XFRichTextEditor : NSView
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSPopUpButton *blockPopup;
@property (nonatomic, strong) NSFont *baseFont;
- (instancetype)initWithFrame:(NSRect)frame baseFont:(NSFont *)font;
- (void)setHTML:(NSString *)html;
- (NSString *)HTML;
/// Return inside a list continues it (next bullet / number); Return on an
/// empty item leaves the list. NO = not in a list, insert normally.
- (BOOL)handleNewline;
@end
