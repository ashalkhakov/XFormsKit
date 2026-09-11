#!/usr/bin/env python3
"""Generates XFDDocumentWindow.xib — the designer's three-pane window.

The xib follows ModelBuilder's dialect (FreeCoreData): Xcode 8 format,
fixed frames + autoresizing masks, one xib serving both toolkits (GNUstep
loads it through GSXib5). Regenerate after changing the row tables below:

    python3 tools/genxib.py > XFDDocumentWindow.xib
"""

SEQ = [0]
def nid():
    """IB object ids are three dash-separated tokens (every id in the
    IB-opened ModelBuilder xib has that shape) — keep it or Interface
    Builder refuses the document."""
    SEQ[0] += 1
    return "xfd-a%d-%03d" % (SEQ[0] // 1000, SEQ[0] % 1000)

FIXED = {}
def fid(name):
    """Stable three-part id for an outlet-referenced element."""
    if name not in FIXED:
        FIXED[name] = "xfd-f%d-%03d" % (len(FIXED) // 1000, len(FIXED) % 1000)
    return FIXED[name]

def label(x, y, w, text, bold=False):
    font = 'smallSystem'
    align = 'left' if bold else 'right'
    return f'''<textField focusRingType="none" horizontalHuggingPriority="251" verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{nid()}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="14"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMinY="YES"/>
<textFieldCell key="cell" controlSize="small" lineBreakMode="clipping" alignment="{align}" title="{text}" id="{nid()}">
<font key="font" metaFont="{font}"/>
<color key="textColor" name="labelColor" catalog="System" colorSpace="catalog"/>
<color key="backgroundColor" name="textBackgroundColor" catalog="System" colorSpace="catalog"/>
</textFieldCell>
</textField>'''

def field(x, y, w, ident, action='inspectorChanged:'):
    conn = f'<connections><action selector="{action}" target="-2" id="{nid()}"/></connections>' if action else ''
    return f'''<textField focusRingType="none" verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="19"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
<textFieldCell key="cell" controlSize="small" scrollable="YES" lineBreakMode="clipping" selectable="YES" editable="YES" sendsActionOnEndEditing="YES" borderStyle="bezel" drawsBackground="YES" id="{nid()}">
<font key="font" metaFont="smallSystem"/>
<color key="textColor" name="controlTextColor" catalog="System" colorSpace="catalog"/>
<color key="backgroundColor" name="textBackgroundColor" catalog="System" colorSpace="catalog"/>
</textFieldCell>
{conn}
</textField>'''

def static_value(x, y, w, ident):
    """Read-only value line (element name readout)."""
    return f'''<textField focusRingType="none" horizontalHuggingPriority="251" verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="14"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
<textFieldCell key="cell" controlSize="small" lineBreakMode="truncatingTail" selectable="YES" title="" id="{nid()}">
<font key="font" metaFont="smallSystem"/>
<color key="textColor" name="labelColor" catalog="System" colorSpace="catalog"/>
<color key="backgroundColor" name="textBackgroundColor" catalog="System" colorSpace="catalog"/>
</textFieldCell>
</textField>'''

def checkbox(x, y, w, title, ident):
    return f'''<button verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="16"/>
<autoresizingMask key="autoresizingMask" flexibleMinY="YES"/>
<buttonCell key="cell" type="check" title="{title}" bezelStyle="regularSquare" imagePosition="left" controlSize="small" inset="2" id="{nid()}">
<behavior key="behavior" changeContents="YES" doesNotDimImage="YES" lightByContents="YES"/>
<font key="font" metaFont="smallSystem"/>
</buttonCell>
<connections><action selector="inspectorChanged:" target="-2" id="{nid()}"/></connections>
</button>'''

def popup(x, y, w, ident, titles):
    first = nid()
    items = f'<menuItem title="{titles[0]}" state="on" id="{first}"/>' + ''.join(
        f'<menuItem title="{t}" id="{nid()}"/>' for t in titles[1:])
    return f'''<popUpButton verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="22"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
<popUpButtonCell key="cell" type="push" title="{titles[0]}" bezelStyle="rounded" alignment="left" controlSize="small" lineBreakMode="truncatingTail" state="on" borderStyle="borderAndBezel" imageScaling="proportionallyDown" inset="2" selectedItem="{first}" id="{nid()}">
<behavior key="behavior" lightByBackground="YES" lightByGray="YES"/>
<font key="font" metaFont="smallSystem"/>
<menu key="menu" id="{nid()}">
<items>{items}</items>
</menu>
</popUpButtonCell>
<connections><action selector="inspectorChanged:" target="-2" id="{nid()}"/></connections>
</popUpButton>'''

def xpathfield(x, y, w, ident):
    """One XFDXPathField: text field + picker button + validation, built
    by the class itself — the xib only reserves the frame."""
    return f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}" customClass="XFDXPathField">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="21"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
</customView>'''

def idreffield(x, y, w, ident):
    """One XFDIDRefField: combo box of the live ids of one element kind
    (typed or picked), built by the class itself — the xib only reserves
    the frame; the controller assigns the kind."""
    return f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}" customClass="XFDIDRefField">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="23"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
</customView>'''

def richfield(x, y, w, ident):
    """One XFDRichTextField: plain text in place, rich XForms 1.1 content
    (inline markup + xf:output) through its own modal editor — built by
    the class itself, the xib only reserves the frame."""
    return f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}" customClass="XFDRichTextField">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="21"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
</customView>'''

def pushbutton(x, y, w, title, action, ident):
    return f'''<button verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{ident}">
<rect key="frame" x="{x}" y="{y}" width="{w}" height="24"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMinY="YES"/>
<buttonCell key="cell" type="push" title="{title}" bezelStyle="rounded" alignment="center" controlSize="small" borderStyle="border" imageScaling="proportionallyDown" inset="2" id="{nid()}">
<behavior key="behavior" pushIn="YES" lightByBackground="YES" lightByGray="YES"/>
<font key="font" metaFont="smallSystem"/>
</buttonCell>
<connections><action selector="{action}" target="-2" id="{nid()}"/></connections>
</button>'''

TAB_H = 672   # inspector tab item view height

def rows(spec):
    """spec: list of (kind, args...) rows laid top-down."""
    out = []
    y = TAB_H - 30
    for row in spec:
        kind = row[0]
        if kind == 'title':
            out.append(static_value(8, y, 264, row[1]))
        elif kind == 'header':
            out.append(label(8, y, 200, row[1], bold=True))
        elif kind == 'field':
            out.append(label(0, y, 92, row[1]))
            out.append(field(98, y - 3, 174, row[2]))
        elif kind == 'xpath':
            out.append(label(0, y, 92, row[1]))
            out.append(xpathfield(98, y - 4, 174, row[2]))
        elif kind == 'richfield':
            out.append(label(0, y, 92, row[1]))
            out.append(richfield(98, y - 4, 174, row[2]))
        elif kind == 'idref':
            out.append(label(0, y, 92, row[1]))
            out.append(idreffield(98, y - 5, 174, row[2]))
        elif kind == 'check':
            out.append(checkbox(98, y, 170, row[1], row[2]))
        elif kind == 'popup':
            out.append(label(0, y, 92, row[1]))
            out.append(popup(98, y - 5, 174, row[2], row[3]))
        elif kind == 'button':
            out.append(pushbutton(98, y - 5, max(110, 8 * len(row[1]) + 24), row[1], row[2], row[3]))
        elif kind == 'note':
            out.append(label(8, y, 260, row[1], bold=False).replace('alignment="right"', 'alignment="left"'))
        y -= 26
    return '\n'.join(out)

# ---- inspector tabs ------------------------------------------------------
# Xcode-IB-style grouping: DMTabBar switches Identity / Attributes /
# Layout; inside Attributes a TABLESS nested tab view shows only the page
# pertinent to the selected tag (switched by the controller, never by the
# user) — the ModelBuilder inspectorKindTabView pattern.

IDENTITY_TAB = rows([
    ('title', fid('identityTitleField')),
    ('field', 'ID', fid('identityIdField')),
])

LAYOUT_TAB = rows([
    ('note', 'No layout attributes in this slice.'),
])

CONTROL_TAB = rows([
    ('xpath', 'Ref', fid('controlRefField')),
    ('xpath', 'Value', fid('controlValueField')),
    ('idref', 'Bind', fid('controlBindField')),
    ('title', fid('controlBindingStatusField')),
    ('button', 'Create Bind from Ref', 'createBindFromRef:', fid('controlCreateBindButton')),
    ('idref', 'Model', fid('controlModelField')),
    ('idref', 'Submission', fid('controlSubmissionField')),
    ('popup', 'Appearance', fid('controlAppearancePopup'), ['(default)', 'minimal', 'compact', 'full']),
    ('check', 'Incremental', fid('controlIncrementalCheckbox')),
    ('field', 'Media Type', fid('controlMediatypeField')),
    ('header', 'Texts'),
    ('richfield', 'Label', fid('controlLabelField')),
    ('richfield', 'Hint', fid('controlHintField')),
    ('richfield', 'Help', fid('controlHelpField')),
    ('richfield', 'Alert', fid('controlAlertField')),
])

BIND_TAB = rows([
    ('xpath', 'Nodeset', fid('bindNodesetField')),
    ('field', 'Type', fid('bindTypeField')),
    ('xpath', 'Calculate', fid('bindCalculateField')),
    ('xpath', 'Constraint', fid('bindConstraintField')),
    ('xpath', 'Required', fid('bindRequiredField')),
    ('xpath', 'Relevant', fid('bindRelevantField')),
    ('xpath', 'Readonly', fid('bindReadonlyField')),
])

SUBMISSION_TAB = rows([
    ('field', 'Resource', fid('submissionResourceField')),
    ('field', 'Method', fid('submissionMethodField')),
    ('popup', 'Replace', fid('submissionReplacePopup'), ['none', 'all', 'instance', 'text']),
    ('idref', 'Instance', fid('submissionInstanceField')),
    ('xpath', 'Ref', fid('submissionRefField')),
    ('idref', 'Bind', fid('submissionBindField')),
])

INSTANCE_TAB = rows([
    ('field', 'Src', fid('instanceSrcField')),
    ('button', 'Edit XML…', 'editInstanceXML:', fid('instanceEditButton')),
    ('note', 'Double-clicking the instance in the outline works too.'),
])

# The Action page is data-driven: one host view the controller fills with
# rows generated from the per-action spec table (every action kind would
# otherwise need its own page and outlet set).
ACTION_TAB = f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{fid('actionRowsHost')}">
<rect key="frame" x="0.0" y="0.0" width="280" height="{TAB_H}"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</customView>'''

ITEM_TAB = rows([
    ('richfield', 'Label', fid('itemLabelField')),
    ('field', 'Value', fid('itemValueField')),
    ('note', 'A fixed choice: label shown, value stored.'),
])

ITEMSET_TAB = rows([
    ('xpath', 'Nodeset', fid('itemsetNodesetField')),
    ('idref', 'Bind', fid('itemsetBindField')),
    ('xpath', 'Label Ref', fid('itemsetLabelRefField')),
    ('xpath', 'Value Ref', fid('itemsetValueRefField')),
    ('note', 'One choice per node; label / value evaluate per node.'),
])

# The Events group: a host view the controller fills with the handler
# table (the selected element's direct child actions) — code-built like
# the Action page.
EVENTS_TAB = f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{fid('eventsHost')}">
<rect key="frame" x="0.0" y="0.0" width="280" height="{TAB_H}"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</customView>'''

HOST_TAB = rows([
    ('note', 'No editable attributes for this element.'),
    ('button', 'New Bound Control…', 'elementCreateBoundControl:', fid('hostNewControlButton')),
    ('note', 'Instance data only: adds a control bound to this node.'),
])

def tab_item(name, body):
    return f'''<tabViewItem label="{name}" identifier="" id="{nid()}">
<view key="view" id="{nid()}">
<rect key="frame" x="0.0" y="0.0" width="280" height="{TAB_H}"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
{body}
</subviews>
</view>
</tabViewItem>'''

# ---- panes ---------------------------------------------------------------

LEFT = f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-p0-lft">
<rect key="frame" x="0.0" y="0.0" width="240" height="720"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<scrollView fixedFrame="YES" horizontalLineScroll="24" horizontalPageScroll="10" verticalLineScroll="24" verticalPageScroll="10" hasHorizontalScroller="NO" usesPredominantAxisScrolling="NO" translatesAutoresizingMaskIntoConstraints="NO" id="{nid()}">
<rect key="frame" x="0.0" y="28" width="240" height="692"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<clipView key="contentView" id="{nid()}">
<rect key="frame" x="0.0" y="0.0" width="240" height="692"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<outlineView verticalHuggingPriority="750" allowsExpansionToolTips="YES" columnAutoresizingStyle="lastColumnOnly" multipleSelection="NO" autosaveColumns="NO" rowHeight="20" indentationPerLevel="13" outlineTableColumn="xfd-w0-col" id="xfd-w0-out">
<rect key="frame" x="0.0" y="0.0" width="240" height="692"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<size key="intercellSpacing" width="3" height="2"/>
<color key="backgroundColor" name="controlBackgroundColor" catalog="System" colorSpace="catalog"/>
<color key="gridColor" name="gridColor" catalog="System" colorSpace="catalog"/>
<tableColumns>
<tableColumn identifier="element" width="220" minWidth="40" maxWidth="1000" id="xfd-w0-col">
<tableHeaderCell key="headerCell" lineBreakMode="truncatingTail" borderStyle="border">
<color key="textColor" name="headerTextColor" catalog="System" colorSpace="catalog"/>
<color key="backgroundColor" name="headerColor" catalog="System" colorSpace="catalog"/>
</tableHeaderCell>
<textFieldCell key="dataCell" lineBreakMode="truncatingTail" selectable="YES" title="Text Cell" id="{nid()}">
<font key="font" metaFont="system"/>
<color key="textColor" name="controlTextColor" catalog="System" colorSpace="catalog"/>
<color key="backgroundColor" name="controlBackgroundColor" catalog="System" colorSpace="catalog"/>
</textFieldCell>
<tableColumnResizingMask key="resizingMask" resizeWithTable="YES"/>
</tableColumn>
</tableColumns>
<connections>
<outlet property="dataSource" destination="-2" id="{nid()}"/>
<outlet property="delegate" destination="-2" id="{nid()}"/>
</connections>
</outlineView>
</subviews>
</clipView>
<scroller key="horizontalScroller" hidden="YES" verticalHuggingPriority="750" horizontal="YES" id="{nid()}">
<rect key="frame" x="0.0" y="0.0" width="240" height="16"/>
<autoresizingMask key="autoresizingMask"/>
</scroller>
<scroller key="verticalScroller" hidden="YES" verticalHuggingPriority="750" horizontal="NO" id="{nid()}">
<rect key="frame" x="224" y="0.0" width="16" height="692"/>
<autoresizingMask key="autoresizingMask"/>
</scroller>
</scrollView>
<segmentedControl verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-seg">
<rect key="frame" x="6" y="4" width="70" height="20"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<segmentedCell key="cell" controlSize="small" borderStyle="border" alignment="left" style="rounded" trackingMode="momentary" id="{nid()}">
<font key="font" metaFont="smallSystem"/>
<segments>
<segment label="+" width="30"/>
<segment label="&#8722;" width="30" tag="1"/>
</segments>
</segmentedCell>
<connections><action selector="plusMinusClicked:" target="-2" id="{nid()}"/></connections>
</segmentedControl>
</subviews>
</customView>'''

CENTER = f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-p0-ctr">
<rect key="frame" x="241" y="0.0" width="578" height="720"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<segmentedControl verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-mod">
<rect key="frame" x="8" y="694" width="140" height="20"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMinY="YES"/>
<segmentedCell key="cell" controlSize="small" borderStyle="border" alignment="left" style="rounded" trackingMode="selectOne" id="{nid()}">
<font key="font" metaFont="smallSystem"/>
<segments>
<segment label="Form" width="60"/>
<segment label="Source" width="60" tag="1"/>
</segments>
</segmentedCell>
<connections><action selector="modeChanged:" target="-2" id="{nid()}"/></connections>
</segmentedControl>
<button verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-dsn">
<rect key="frame" x="156" y="696" width="76" height="16"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMinY="YES"/>
<buttonCell key="cell" type="check" title="Design" bezelStyle="regularSquare" imagePosition="left" controlSize="small" inset="2" id="{nid()}">
<behavior key="behavior" changeContents="YES" doesNotDimImage="YES" lightByContents="YES"/>
<font key="font" metaFont="smallSystem"/>
</buttonCell>
<connections><action selector="toggleDesignMode:" target="-2" id="{nid()}"/></connections>
</button>
<tabView fixedFrame="YES" type="noTabsNoBorder" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-ctb">
<rect key="frame" x="0.0" y="0.0" width="578" height="690"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<font key="font" metaFont="system"/>
<tabViewItems>
<tabViewItem label="Form" identifier="" id="{nid()}">
<view key="view" id="{nid()}">
<rect key="frame" x="0.0" y="0.0" width="578" height="690"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-pvh">
<rect key="frame" x="0.0" y="0.0" width="578" height="690"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</customView>
</subviews>
</view>
</tabViewItem>
<tabViewItem label="Source" identifier="" id="{nid()}">
<view key="view" id="{nid()}">
<rect key="frame" x="0.0" y="0.0" width="578" height="690"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-srh">
<rect key="frame" x="0.0" y="30" width="578" height="660"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</customView>
<button verticalHuggingPriority="750" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{nid()}">
<rect key="frame" x="488" y="3" width="84" height="24"/>
<autoresizingMask key="autoresizingMask" flexibleMinX="YES" flexibleMaxY="YES"/>
<buttonCell key="cell" type="push" title="Apply" bezelStyle="rounded" alignment="center" controlSize="small" borderStyle="border" imageScaling="proportionallyDown" inset="2" id="{nid()}">
<behavior key="behavior" pushIn="YES" lightByBackground="YES" lightByGray="YES"/>
<font key="font" metaFont="smallSystem"/>
</buttonCell>
<connections><action selector="applySource:" target="-2" id="{nid()}"/></connections>
</button>
</subviews>
</view>
</tabViewItem>
</tabViewItems>
</tabView>
</subviews>
</customView>'''

KIND_TABS = f"""<tabView fixedFrame="YES" type="noTabsNoBorder" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-ktb">
<rect key="frame" x="0.0" y="0.0" width="280" height="{TAB_H}"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<font key="font" metaFont="system"/>
<tabViewItems>
{tab_item('Control', CONTROL_TAB)}
{tab_item('Bind', BIND_TAB)}
{tab_item('Submission', SUBMISSION_TAB)}
{tab_item('Instance', INSTANCE_TAB)}
{tab_item('Element', HOST_TAB)}
{tab_item('Action', ACTION_TAB)}
{tab_item('Item', ITEM_TAB)}
{tab_item('Itemset', ITEMSET_TAB)}
</tabViewItems>
</tabView>"""

ATTRIBUTES_TAB_BODY = KIND_TABS

RIGHT = f'''<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-p0-rgt">
<rect key="frame" x="820" y="0.0" width="280" height="720"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<customView fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-bar" customClass="DMTabBar">
<rect key="frame" x="0.0" y="698" width="280" height="22"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" flexibleMinY="YES"/>
</customView>
<tabView fixedFrame="YES" type="noTabsNoBorder" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-itb">
<rect key="frame" x="0.0" y="0.0" width="280" height="{TAB_H}"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<font key="font" metaFont="system"/>
<tabViewItems>
{tab_item('Identity', IDENTITY_TAB)}
{tab_item('Attributes', ATTRIBUTES_TAB_BODY)}
{tab_item('Layout', LAYOUT_TAB)}
{tab_item('Events', EVENTS_TAB)}
</tabViewItems>
</tabView>
</subviews>
</customView>'''

OUTLETS = [
    ('window', "xfd-w0-win"),
    ('outline', "xfd-w0-out"),
    ('plusMinusControl', "xfd-w0-seg"),
    ('modeControl', "xfd-w0-mod"),
    ('designModeCheckbox', "xfd-w0-dsn"),
    ('centerTabView', "xfd-w0-ctb"),
    ('previewHost', "xfd-w0-pvh"),
    ('sourceHost', "xfd-w0-srh"),
    ('inspectorTabBar', "xfd-w0-bar"),
    ('inspectorTabView', "xfd-w0-itb"),
    ('identityTitleField', fid('identityTitleField')),
    ('identityIdField', fid('identityIdField')),
    ('inspectorKindTabView', 'xfd-w0-ktb'),
    ('actionRowsHost', fid('actionRowsHost')),
    ('eventsHost', fid('eventsHost')),
    ('itemLabelField', fid('itemLabelField')),
    ('itemValueField', fid('itemValueField')),
    ('itemsetNodesetField', fid('itemsetNodesetField')),
    ('itemsetBindField', fid('itemsetBindField')),
    ('itemsetLabelRefField', fid('itemsetLabelRefField')),
    ('itemsetValueRefField', fid('itemsetValueRefField')),
    ('controlRefField', fid('controlRefField')),
    ('controlValueField', fid('controlValueField')),
    ('controlAppearancePopup', fid('controlAppearancePopup')),
    ('controlIncrementalCheckbox', fid('controlIncrementalCheckbox')),
    ('controlMediatypeField', fid('controlMediatypeField')),
    ('controlLabelField', fid('controlLabelField')),
    ('controlHintField', fid('controlHintField')),
    ('controlHelpField', fid('controlHelpField')),
    ('controlAlertField', fid('controlAlertField')),
    ('bindNodesetField', fid('bindNodesetField')),
    ('bindTypeField', fid('bindTypeField')),
    ('bindCalculateField', fid('bindCalculateField')),
    ('bindConstraintField', fid('bindConstraintField')),
    ('bindRequiredField', fid('bindRequiredField')),
    ('bindRelevantField', fid('bindRelevantField')),
    ('bindReadonlyField', fid('bindReadonlyField')),
    ('submissionResourceField', fid('submissionResourceField')),
    ('submissionMethodField', fid('submissionMethodField')),
    ('submissionReplacePopup', fid('submissionReplacePopup')),
    ('submissionInstanceField', fid('submissionInstanceField')),
    ('submissionRefField', fid('submissionRefField')),
    ('instanceSrcField', fid('instanceSrcField')),
    ('controlBindField', fid('controlBindField')),
    ('controlCreateBindButton', fid('controlCreateBindButton')),
    ('hostNewControlButton', fid('hostNewControlButton')),
    ('controlModelField', fid('controlModelField')),
    ('controlSubmissionField', fid('controlSubmissionField')),
    ('submissionBindField', fid('submissionBindField')),
    ('controlBindingStatusField', fid('controlBindingStatusField')),
]

outlets_xml = '\n'.join(
    f'<outlet property="{prop}" destination="{dest}" id="{nid()}"/>' for prop, dest in OUTLETS)

DOC = f'''<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.Cocoa.XIB" version="3.0" toolsVersion="24127" targetRuntime="MacOSX.Cocoa" propertyAccessControl="none" useAutolayout="YES" customObjectInstantitationMethod="direct">
    <dependencies>
        <deployment identifier="macosx"/>
        <plugIn identifier="com.apple.InterfaceBuilder.CocoaPlugin" version="24127"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <customObject id="-2" userLabel="File's Owner" customClass="XFDWindowController">
            <connections>
{outlets_xml}
            </connections>
        </customObject>
        <customObject id="-1" userLabel="First Responder" customClass="FirstResponder"/>
        <customObject id="-3" userLabel="Application" customClass="NSObject"/>
        <window title="XFormsDesigner" allowsToolTipsWhenApplicationIsInactive="NO" autorecalculatesKeyViewLoop="NO" releasedWhenClosed="NO" animationBehavior="default" id="xfd-w0-win">
            <windowStyleMask key="styleMask" titled="YES" closable="YES" miniaturizable="YES" resizable="YES"/>
            <windowPositionMask key="initialPositionMask" leftStrut="YES" rightStrut="YES" topStrut="YES" bottomStrut="YES"/>
            <rect key="contentRect" x="180" y="120" width="1100" height="720"/>
            <rect key="screenRect" x="0.0" y="0.0" width="1920" height="1055"/>
            <value key="minSize" type="size" width="900" height="560"/>
            <view key="contentView" wantsLayer="YES" id="{nid()}">
                <rect key="frame" x="0.0" y="0.0" width="1100" height="720"/>
                <autoresizingMask key="autoresizingMask"/>
                <subviews>
                    <splitView fixedFrame="YES" arrangesAllSubviews="NO" dividerStyle="thin" vertical="YES" translatesAutoresizingMaskIntoConstraints="NO" id="xfd-w0-spl">
                        <rect key="frame" x="0.0" y="0.0" width="1100" height="720"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
{LEFT}
{CENTER}
{RIGHT}
                        </subviews>
                        <holdingPriorities>
                            <real value="250"/>
                            <real value="250"/>
                            <real value="250"/>
                        </holdingPriorities>
                        <connections><outlet property="delegate" destination="-2" id="{nid()}"/></connections>
                    </splitView>
                </subviews>
            </view>
        </window>
    </objects>
</document>'''

print(DOC)
