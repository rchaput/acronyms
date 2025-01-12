This test ensures that non-alpha-numerical characters can be used as part of
acronyms (both shortnames and longnames).

Shortnames are especially important to check because they are converted to
- the acronym's key if is not specified;
- the acronym's ID, which is used in links to the List Of Acronyms.

The key should not be a problem, except perhaps in shortcodes? It should
not contain any spaces. But the key can be specified on its own if something
other than the shortname must be used anyway.

The link ID is a bigger problem: it is used to create an anchor, which
only accept some valid characters. This test ensures that a proper sanitization
happens and that anchors still work despite the non-alpha-numerical characters.