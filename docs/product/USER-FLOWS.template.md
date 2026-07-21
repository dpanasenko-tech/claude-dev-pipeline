# User Flows — <feature>

> One flow per heading. Cover happy + at least one edge path. Keep steps imperative.

## Flow: <name>
- **Actor**: <persona>
- **Trigger**: <event or action that starts the flow>
- **Preconditions**: <state required before start>
- **Steps**:
  1. <user/system action>
  2. ...
- **Outcome**: <observable end state>
- **Failure modes**:
  - <error case> → <how system responds, how user recovers>

## Flow: <edge case name>
- (same structure)

## Cross-flow notes
- Idempotency: <which actions are safe to retry?>
- Concurrency: <what happens if two actors act at once?>
- Permissions: <what does each role see/do?>
