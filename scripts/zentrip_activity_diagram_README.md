# ZenTrip activity diagrams

The editable flow model is in `zentrip_activity_diagram_model.py`. It records
nodes, labeled branches, page links, endpoints, footnotes, flow descriptions,
and documented limitations. `build-zentrip-activity-diagram.py` validates the
cross-page graph, renders each page and standalone HTML viewer, then invokes
`build-zentrip-activity-docx.cjs` to create the Word document.

## Rebuild

From the project root, with the project Node dependencies installed:

```sh
python3 scripts/build-zentrip-activity-diagram.py
```

The build checks that:

- there is exactly one Start and one End across the complete diagram;
- each off-page connector letter occurs once as an exit and once as an entry;
- all local edges reference existing nodes;
- every decision's outgoing labels match its declared branches;
- every non-Start/End node has incoming and outgoing paths; and
- every node is reachable from the single Start.

Generated SVG, Mermaid source, high-resolution PNG, HTML viewer, manifest, and
Word output are written to `generated-artifacts/`. Edit the model rather than
the generated files. The master page's module nodes are clickable in the HTML
viewer, and each `.mmd` file can be edited independently.

## Important flow facts

The diagrams represent the current app, not a proposed implementation. In
particular, flight/hotel provider lookups and the My Trips reads are concurrent;
Zen AI server persistence and local transcript persistence occur sequentially;
attraction view counting is fire-and-forget and does not block attraction
booking; and checkout is simulated rather than supplier ticketing/payment.
