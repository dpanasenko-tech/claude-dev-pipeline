# API Spec — <feature or service>

> One section per endpoint. Keep request/response examples minimal but real.

## Conventions
- Base URL: `<https://api.example.com/v1>`
- Auth: <Bearer JWT | session cookie | API key>
- Content-Type: `application/json`
- Error model: see `Errors` below.

## Endpoints

### `<METHOD> /resource`
- **Purpose**: one sentence.
- **Auth**: <required role/scope>
- **Request**:
  ```json
  {
    "field": "type — constraints"
  }
  ```
- **Response 200**:
  ```json
  {
    "id": "uuid",
    "field": "value"
  }
  ```
- **Errors**: 400, 401, 403, 404, 409, 422, 429, 5xx (only list those used).
- **Idempotency**: <key header? safe to retry?>
- **Rate limits**: <limit and bucket>
- **Pagination**: <cursor | offset | none>
- **Observability**: log fields, metric names, trace span.

### `<METHOD> /resource/{id}`
- (same structure)

## Errors
- Standard shape:
  ```json
  {
    "error": {
      "code": "string",
      "message": "human-readable",
      "details": { "field": "reason" }
    }
  }
  ```
- Codes: `validation_failed`, `unauthorized`, `forbidden`, `not_found`, `conflict`, `rate_limited`, `internal`.

## Versioning
- URI versioned (`/v1`). Breaking changes require a new version.
- Deprecation policy: <N months>, `Deprecation` + `Sunset` headers.

## Open questions
- <list>
