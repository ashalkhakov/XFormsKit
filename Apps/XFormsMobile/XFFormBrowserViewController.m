/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFFormBrowserViewController.h"
#import "XFMobileForm.h"
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFFormViewController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface XFFormBrowserViewController () <UIDocumentPickerDelegate>
/// The form on screen. Held here, not by the pushed controller: the
/// controller shows a processor, and this owns the document — its file
/// access included — until another form replaces it.
@property (nonatomic, strong, nullable) XFMobileForm *form;
/// The sample forms carried in the app bundle, by file name.
@property (nonatomic, copy) NSArray<NSURL *> *samples;
@end

@implementation XFFormBrowserViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"XForms", nil);
    self.samples = [[self class] bundledSamples];
    UIBarButtonItem *open =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(chooseForm)];
    open.accessibilityLabel = NSLocalizedString(@"Open form", nil);
    self.navigationItem.rightBarButtonItem = open;
    if (self.samples.count == 0) {
        [self installPlaceholder];   // a build without the samples folder
    }
}

/// The forms in the bundled `Samples` folder — the same set the macOS
/// viewer lists under File ▸ Open Sample, carried as a folder reference so
/// the resources some of them pull in (`counties.xml`, `flag.svg`,
/// `textarea.css`) sit beside them and resolve.
///
/// Only `.xhtml`: everything else in there is one of those resources, not
/// a form to open.
+ (NSArray<NSURL *> *)bundledSamples
{
    NSURL *folder = [[[NSBundle mainBundle] resourceURL]
        URLByAppendingPathComponent:@"Samples" isDirectory:YES];
    NSArray<NSURL *> *found = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:folder
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:NULL];
    NSMutableArray<NSURL *> *forms = [NSMutableArray array];
    for (NSURL *url in found) {
        if ([[url pathExtension] caseInsensitiveCompare:@"xhtml"] == NSOrderedSame) {
            [forms addObject:url];
        }
    }
    [forms sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [[a lastPathComponent] localizedStandardCompare:[b lastPathComponent]];
    }];
    return forms;
}

/// The empty state, behind the table, for a build whose bundle carries
/// no samples. UIContentUnavailableConfiguration would be the modern
/// spelling, but it needs iOS 17 and the framework targets 15.
- (void)installPlaceholder
{
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"doc.text"]];
    icon.tintColor = [UIColor tertiaryLabelColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.heightAnchor constraintEqualToConstant:56].active = YES;

    UILabel *caption = [[UILabel alloc] init];
    caption.text = NSLocalizedString(@"No form open", nil);
    caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    caption.textColor = [UIColor secondaryLabelColor];
    caption.textAlignment = NSTextAlignmentCenter;

    UILabel *detail = [[UILabel alloc] init];
    detail.text = NSLocalizedString(@"Choose an XForms document to fill in.", nil);
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    detail.textColor = [UIColor tertiaryLabelColor];
    detail.textAlignment = NSTextAlignmentCenter;
    detail.numberOfLines = 0;

    UIButton *open = [UIButton buttonWithType:UIButtonTypeSystem];
    [open setTitle:NSLocalizedString(@"Open Form…", nil) forState:UIControlStateNormal];
    open.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [open addTarget:self action:@selector(chooseForm)
      forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[ icon, caption, detail, open ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *background = [[UIView alloc] initWithFrame:CGRectZero];
    [background addSubview:stack];
    self.tableView.backgroundView = background;
    UILayoutGuide *safe = background.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor
                                                         constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor
                                                       constant:-24],
    ]];
}

#pragma mark - The sample list

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return self.samples.count ? 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView; (void)section;
    return (NSInteger)self.samples.count;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForHeaderInSection:(NSInteger)section
{
    (void)tableView; (void)section;
    return NSLocalizedString(@"Samples", nil);
}

- (NSString *)tableView:(UITableView *)tableView
    titleForFooterInSection:(NSInteger)section
{
    (void)tableView; (void)section;
    return NSLocalizedString(@"Or open a form of your own with the folder button.", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sample"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sample"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSURL *sample = self.samples[(NSUInteger)indexPath.row];
    cell.textLabel.text = [[sample lastPathComponent] stringByDeletingPathExtension];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openFormAtURL:self.samples[(NSUInteger)indexPath.row]];
}

#pragma mark - Choosing

/// The types a form document comes as. `.xhtml` is the usual one and has
/// no constant of its own; XML and HTML are here because forms are
/// written and served as both.
+ (NSArray<UTType *> *)formContentTypes
{
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *xhtml = [UTType typeWithFilenameExtension:@"xhtml"];
    if (xhtml) {
        [types addObject:xhtml];
    }
    [types addObject:UTTypeXML];
    [types addObject:UTTypeHTML];
    return types;
}

- (void)chooseForm
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:[[self class] formContentTypes]];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    (void)picker;
    NSURL *url = urls.firstObject;
    if (url) {
        [self openFormAtURL:url];
    }
}

#pragma mark - Opening

- (BOOL)openFormAtURL:(NSURL *)url
{
    NSError *error = nil;
    XFMobileForm *form = [XFMobileForm formWithContentsOfURL:url error:&error];
    if (form == nil) {
        [self reportFailureToOpen:url error:error];
        return NO;
    }
    self.form = form;   // replaces the previous form, closing its models
    XFFormViewController *view =
        [[XFFormViewController alloc] initWithProcessor:form.processor];
    view.title = form.title;
    [self.navigationController pushViewController:view animated:YES];
    return YES;
}

/// A form that will not load is the interesting case for a viewer: the
/// engine's error says which element or expression is at fault, so it is
/// shown rather than reduced to "could not open".
- (void)reportFailureToOpen:(NSURL *)url error:(NSError *)error
{
    NSString *reason = error.localizedDescription.length
        ? error.localizedDescription
        : NSLocalizedString(@"The document could not be read.", nil);
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[url lastPathComponent]
                         message:reason
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
