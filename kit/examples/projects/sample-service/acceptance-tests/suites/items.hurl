# 1. POST /items -> 201 created
POST {{baseUrl}}/api/v1/items
Content-Type: application/json
{
  "key": "acc-test.{{newUuid}}",
  "name": "Acceptance item"
}
HTTP 201
[Captures]
itemKey: jsonpath "$.key"
itemId: jsonpath "$.id"
itemVersion: jsonpath "$.version"
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.id" isString
jsonpath "$.key" matches "^acc-test\\."
jsonpath "$.name" == "Acceptance item"
jsonpath "$.status" == "ACTIVE"
jsonpath "$.version" isInteger


# 2. GET /items/{id} -> 200 the created item
GET {{baseUrl}}/api/v1/items/{{itemId}}
HTTP 200
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.id" == "{{itemId}}"
jsonpath "$.key" == "{{itemKey}}"
jsonpath "$.version" == {{itemVersion}}


# 3. PUT /items/{id} -> 200 updated
PUT {{baseUrl}}/api/v1/items/{{itemId}}
Content-Type: application/json
{
  "name": "Renamed item",
  "version": {{itemVersion}}
}
HTTP 200
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.id" == "{{itemId}}"
jsonpath "$.name" == "Renamed item"
jsonpath "$.version" isInteger


# @requires 1.2.0 skip=skipItemArchive
# 4. POST /items/{id}/archive -> 200 archived
POST {{baseUrl}}/api/v1/items/{{itemId}}/archive
[Options]
skip: {{skipItemArchive}}
HTTP 200
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.id" == "{{itemId}}"
jsonpath "$.status" == "ARCHIVED"


# 5. GET /items/{unknown} -> 404 ProblemDetail
GET {{baseUrl}}/api/v1/items/00000000-0000-0000-0000-000000000000
HTTP 404
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.status" == 404
jsonpath "$.type" contains "404"
jsonpath "$.detail" isString
jsonpath "$.detail" matches ".+"


# @requires-env store-unavailable skip=skipStoreUnavailable
# 6. GET /items/{id} -> 503 while the store is down
GET {{baseUrl}}/api/v1/items/{{itemId}}
[Options]
skip: {{skipStoreUnavailable}}
max-time: 15s
HTTP 503
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.status" == 503
jsonpath "$.type" contains "503"
jsonpath "$.detail" isString
jsonpath "$.detail" matches ".+"
