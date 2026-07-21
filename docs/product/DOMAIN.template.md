# Domain Model — <area>

> One file per bounded context. Keep entity definitions tight.

## Glossary
- **<Term>** — definition in one sentence.
- **<Term>** — definition.

## Entities
For each entity:

### <EntityName>
- **Purpose**: <one sentence>
- **Identifier**: <field>
- **Fields**: name, type, required?, notes
- **Invariants** (must always hold):
  - <invariant>
- **Lifecycle / states**: <created → ... → archived>
- **Owns**: <child entities>
- **References**: <related entities>

## Relationships
- `<EntityA>` 1—N `<EntityB>` because <reason>.

## Authorization model
- Who can read/write each entity, and on what basis (role, ownership, scope).

## Out of scope for this doc
- Implementation details (DB schema, ORM).
