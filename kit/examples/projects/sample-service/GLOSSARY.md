# orders-service

The domain language of the `orders-service` microservice. The `domain-modeling` skill adds a
term when a discussion settles its meaning (format:
`../../.agents/skills/domain-modeling/GLOSSARY-FORMAT.md`).

## Language

**Item**:
A record that the service stores, named by a unique key.
_Avoid_: Product, entry, row

**Archived item**:
An item that the service keeps but no longer serves as active; its status is `ARCHIVED`.
_Avoid_: Deleted item, removed item
