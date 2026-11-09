# Forms a host answers: its own scheme, its errors, its warnings

Some forms do not talk to a web service of their own. ORMKit generates one
for each form its model has: the form's data is read from `form:read`, a
reference's choices from `form:choices/<name>`, and the form is saved to
`form:save`. What stands behind those names is the app's business: its
Core Data store when it works offline, its OData service when it is
online. The form names what it reads and writes; the host says where.

XFormsKit gives the host three things for that: a transport given at
construction, which answers its own scheme; errors it found after a
refused submission, shown at their fields; and warnings, shown without
blocking anything.

## The host's transport

    XFSchemeTransport *transport = [[XFSchemeTransport alloc] init];
    [transport setHandler:^XFSubmissionResponse *(XFSubmissionRequest *request, NSError **error) {
        … // request.URLString is "form:read", "form:choices/driver?vehicle=V1", "form:save"
    } forScheme:@"form"];
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml baseURL:url
                                                       transport:transport error:&error];

- **Given at construction.** A processor constructs its models, loads
  their instances and runs `xforms-ready` before it returns, so a
  transport set on `model.transport` afterwards misses the instance
  `src` and every submission a ready handler sends.
  `+processorWithXMLString:baseURL:transport:error:` and
  `+processorWithContentsOfURL:transport:error:` give it to every model
  first (subforms' too); `processor.transport` is it.
- **Instance `src`.** `file:`, `http:`, `https:` and `data:` are read as
  they always were. Any other scheme is asked of the model's transport,
  as a `get`; a 2xx body is the instance (its media type the response's,
  where the instance names none). No transport: the old behaviour (an
  `xforms-link-exception`).
- **Submissions** were always the transport's, whatever the scheme. A
  `get` submission with a `ref` sends the instance's leaf values as the
  query (`form:choices/driver?id=&vehicle=V1&…`), which is how a choices
  read learns what it depends on.
- **`XFSchemeTransport`** answers the schemes the host registers, by
  handler or by transport, case-insensitively, and passes every other
  request to `inner` (an `XFHTTPSubmissionTransport` unless set). Note
  that a transport given this way replaces the processor's
  `defaultTransport` for the models, so plain HTTP goes through `inner`'s
  cookie jar.
- **Threads.** A submission with `mode="asynchronous"` calls the transport
  off the main thread. A handler that touches main-thread state (a
  managed object context) should be given synchronous submissions, or hop
  to its queue itself.
- **Validation.** XForms validates before every submission that has
  `validate` true, the default, `get` included: a read or a choices
  submission over a new form, its required fields still empty, would be
  refused (`validation-error`). Those carry `validate="false"`.

## Errors the host found

A store's validation or a service's 400 refuses what XForms could not
check alone (a rule across objects, a key already taken). The host maps
the refusal to the instance's nodes and says so:

    NSArray<NSString *> *formLevel =
        [processor.model setHostErrors:@{ @"mileage" : @"Each meter reading is above the one before.",
                                          @"" : @"The vehicle was sold." }];

- Each key is an XPath from the default instance's document element; ""
  or one that selects nothing is said of the form as a whole, returned
  and kept in `model.hostMessages`, for the host to show where it shows
  such things.
- A node with an error makes the controls bound to it invalid
  (`control.valid` is NO, `xforms-invalid` is dispatched) and its
  `shownAlert` is the host's message in place of the form's `xf:alert`;
  `control.hostError` is the message.
- It is gone when the node's value changes, when a submission that sent
  data is done, or when the host calls `-clearHostErrors`; a new
  `-setHostErrors:` replaces the old ones. `-setHostError:forNode:` says
  one.
- It is no MIP: it does not block a submission. The host is the one that
  refused, and it refuses again if it must.

## Warnings

A warning is shown at its field and never makes it invalid or stands in
the way of a submission: a rule that ought to hold (ORMKit's deontic
constraints), not one that must.

- **The host's:** `-[XFModel setHostWarning:forNode:]`; nil takes it away.
- **The document's:** an extension element in the model,

      <xf:model xmlns:xfk="urn:xformskit:extensions">
        <xfk:warning ref="fuel" test=". = 'Diesel'">This car does not use that fuel.</xfk:warning>
      </xf:model>

  `ref` selects nodes from the default instance's document element; for
  each, `test` is evaluated with that node as its context, and where it
  holds the text is the node's warning. Evaluated at every revalidate.
  Other processors ignore the element, as XForms 1.1 has them do with
  foreign elements.
- `control.warning` is the host's, else the document's.

## How they are shown

- **AppKit:** the red ! badge's text is `shownAlert` (the tooltip too);
  a warning is an amber ! badge after it, its text in the same floating
  box as the others.
- **UIKit:** the note row under the field is the host's error where it is
  invalid, else the warning (`noteIsWarning`, drawn in orange, read as
  "Warning: …"), else the hint.
