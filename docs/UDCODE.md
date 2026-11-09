# XForms in UDCode

XFormsKit ships a [UDCode](https://github.com/ashalkhakov/UDCodeKit) extension,
XForms, which lets you edit XHTML+XForms forms (`.xhtml`) inside UDCode as
part of a project. The designer is XFormsDesigner's (XFormsDesignKit): the
form running live, design mode, the outline, the Identity, Attributes and
Events inspectors, the library of what can go in a form, and the events
console. XFormsDesigner remains its own app, built on the same framework.

## Installing it

Each XFormsKit release attaches a package for each platform:

| UDCode on | Package |
|---|---|
| macOS, Apple silicon | `xforms-<version>-darwin-arm64.udcx` |
| macOS, Intel | `xforms-<version>-darwin-x64.udcx` |
| Linux (the AppImage), x86_64 | `xforms-<version>-linux-x64.udcx` |
| Linux, aarch64 | `xforms-<version>-linux-arm64.udcx` |
| Windows | `xforms-<version>-win32-x64.udcx` |

Install it with **UDCode > Extensions… > Install from Package…**, or from a
shell with `UDCode --install-extension xforms-<version>-<platform>.udcx`, then
start UDCode again. A package states which UDCode versions it is for
(`engines.udcode` in its `package.json`: 0.22.2 and later 0.22 releases), and UDCode refuses
one built for another version or another platform.

## Using it

Opening an `.xhtml` file from the project navigator shows the form in a tab
of its own, when the file is a form: XHTML with the XForms namespace in it.
Any other XHTML opens as text, in the XML mode's colours, as it does without
the extension. The designer's parts spread over UDCode's window the way an
Xcode editor's do:

| Part | Where it goes in UDCode |
|---|---|
| The form, running; its Design mode (click an element to select it, drag it to move it) | The tab |
| The outline of the form's elements, with + and − | The tab's Document Outline, on the form's left |
| The Identity, Attributes and Events inspectors | The inspector pane's tabs, after **File** |
| The events console | The bottom area, beside the debugger and the terminal (C) |
| What can go in a form: controls, containers, choices, the model's parts, actions | The **Library**: View > Show Library (⇧⌘L); double-click one to put it in |
| Insert Element…, Delete Element, Reset Instance Data | The **Editor** menu's Form |

These parts are shown while the form's tab is in front and go away when
another tab comes forward. The Attributes inspector shows the page for what
is selected: a control, a bind, a submission, an instance, an action, an
item or itemset, or any other element. Double-clicking a handler in the
Events inspector selects it and brings Attributes forward. The events
console traces the form's events while its tab is in front.

The form is stored as the document's text. Each change you make in the
designer is written back to that text, so the things UDCode does for text
files work here too:

- **Undo** and **Redo** are the document's own. Undoing restores the text
  and reads the form again, keeping the selected element selected where it
  still exists.
- **Saving** and the tab's unsaved dot are the document's.
- **Source control** shows what changed. Each change touches only the lines
  that differ. One exception is the first change to a file another tool
  wrote: XFormsKit writes the root element's start tag its own way (its
  namespace declarations on one line), which then differs from the file's.
- **View > Open as Text** shows the form's XML in a normal editor tab, beside
  the designer's. The two tabs are the same document: edits made in the text
  appear in the designer, and the designer's in the text. The designer's own
  Source view is not shown in UDCode: the text tab is the source.

A file that has XForms in it but is not a form that can be read (broken XML,
say) opens with a message explaining why, and offers to show it as text.

## How it is built

`UDCodeExtension/` contains the extension:

- **`XFUExtension`**, its principal class. It declares the `xforms` mode in
  `LanguageInfo.plist`, which borrows the XML mode's grammar; an installed
  extension's modes are registered after UDCode's own, so it takes `.xhtml`
  from the XML mode. It provides the editor for documents of that mode that
  are forms, and adds the Form menu (`XFUEditorMenus.xib`) to UDCode's Editor
  menu.
- **`XFUEditorViewController`**, the tab, loaded from `XFUEditor.xib`: the
  Document Outline and the preview side by side. It holds an `XFDFormEditor`
  over the text, with an undo manager that records nothing, because the
  text's undo manager is the undo. The designer's parts (XFormsDesignKit's
  view controllers over that form editor) go to UDCode's panes through
  `UDEditorPanes`. The form editor's change notices are written as one
  `applyEdits:` call once the change is done (one action is several of the
  commands' changes), which undoes as a single step. When the text changes
  from outside the designer, the tab reads it again: immediately if the tab
  is showing, otherwise after a short delay.
- **`XFUTextDiff`**, a Myers line diff (ORMKit's and RDLKit's). It produces
  the runs of lines that differ, each starting and ending on a line boundary,
  so an edit never splits a CRLF.

It builds against UDCode's SDK, the `udcodekit` archives attached to each
UDCode release, pinned by `UDCODEKIT_VERSION` in `.github/pins.env`, and on
the same GNUstep stack as that UDCode release (`GNUSTEP_PATCHES_VERSION`). At
run time the extension uses UDCode's own copies of these, because two copies
of the same classes cannot be loaded into one process. On GNUstep the top
`GNUmakefile` builds it only where the SDK is installed. On a Mac,
`Makefile.apple` builds it only where `.deps` contains
`UDCodeKit.xcframework`.

`Scripts/udcx.sh <version> <directory>` packages it for the platform it runs
on:

- **The bundle carries what UDCode lacks.** On GNUstep, XFormsDesignKit is
  compiled into the bundle and its XIBs are among the bundle's resources
  (`Sources/XFormsDesignKit/files.make` lists them for both). It can't be a
  framework inside the bundle there: Windows looks for the bundle's libraries
  only beside the bundle's DLL, and gnustep-base would look for a framework's
  resources elsewhere. XFormsKit's library goes next to the binary, with what
  it links that UDCode may not have (Opal, corebase); on Linux they get an
  `$ORIGIN` runpath. On a Mac, XFormsKit and XFormsDesignKit are frameworks
  in the bundle's `Contents/Frameworks`.
- **What UDCode has is left out:** GNUstep's base and GUI, UDCodeKit and the
  system's libraries. The running UDCode's copies are used.
- **Licences:** XFormsKit's own (LGPL 2.1, with its source at the release tag
  that package.json's `repository` points to), DMTabBar's and
  JUInspectorView's (MIT), which the designer's inspector uses.
- **On a Mac** it is signed with `$CODESIGN_IDENTITY`. UDCode's hardened
  runtime loads only code signed by its own team, and the release workflows
  sign the package as they sign the apps, then notarize it.

The release workflows run that script through `.github/release/udcode.conf`
(gnustep-release-actions' `scripts/udcode-extension.sh`) and attach each
package to the release.

The tests in `UDCodeExtension/Tests` (`XFUTests`, run by `make check` and by
`make -f Makefile.apple check`, the `XForms` scheme) drive the tab through
UDCode's own document and text model. They check that:

- a form opens in the designer without its text changing, and XHTML without
  XForms is left as text;
- a change is one edit of the lines it changed, which the text's undo takes
  back, the selected element staying selected;
- a text changed elsewhere is read again;
- a text that is not a form says why, and offers it as text;
- the inspectors, the console and the library are UDCode's panes', and the
  Events inspector asks for the Attributes inspector;
- the console traces while the tab is in a window, and not after;
- the Form menu's items are there and enabled as the selection allows;
- the line diff turns one text into the other.
