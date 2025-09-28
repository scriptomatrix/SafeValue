# SafeValue

SafeValue is a **fluent value validation helper for Roblox Luau**. It wraps raw values in a lightweight object that applies chained validators, emits descriptive errors, and falls back to safe defaults.

## Why use SafeValue?
- **Consistent data hygiene**: Centralize validation logic instead of sprinkling ad-hoc `if` checks.
- **Readable pipelines**: Chain validators such as `:Type()` and `:Range()` for self-documenting code.
- **Safer fallbacks**: Automatically return a default when validation fails.
- **Batch workflows**: Validate many values at once with `SafeValue.ValidateAll()` and aggregate results.

## Features
- **Fluent validators**: Chain `Type`, `Min`, `Max`, `Range`, `Pattern`, `Enum`, `Custom`, `InstanceOf`, `HasKey`, `HasKeys`, and `Schema` checks.
- **Automatic fallbacks**: Supply a default value that is returned whenever validation fails.
- **Aggregated validation**: Call `SafeValue.ValidateAll` to validate multiple values and gather results in one pass.
- **Detailed error messages**: Receive the latest errors directly from `Validate()` and via `GetErrors()`.

## Installation
1. Place `SafeValue.luau` inside a ModuleScript within your Roblox project.
2. Require the module from scripts that need validation:
   ```lua
   local SafeValue = require(path.to.SafeValue)
   ```

## Quick Start
```lua
local SafeValue = require(SafeValueModule)

local health = SafeValue(100, 50, "Health")
    :Type({"number"})
    :Min(0)
    :Max(200)

local sanitizedHealth, isValid, errors = health:Validate()
if not isValid then
    for _, err in ipairs(errors) do
        warn(err)
    end
end
```

## API Reference

### Creating a SafeValue instance
`SafeValue(value: any, defaultValue: any?, valueName: string?) -> SafeValueClass`
- Wraps `value` and optionally defines a default fallback and a display name used in aggregated results.

### Validation chaining methods
All validators return the same `SafeValue` instance so they can be chained. Re-applying a validator overrides the previous configuration of that kind.

| Validator | Signature | What it checks |
| --- | --- | --- |
| `Type` | `Type(Types: {string})` | `type(value)` matches **any** of the allowed Luau types (e.g. `"string"`, `"number"`). Multiple entries let values satisfy several acceptable shapes. |
| `Min` | `Min(minimum: number)` | Numeric values are `>= minimum`. Strings/tables must have length `>= minimum`. |
| `Max` | `Max(maximum: number)` | Numeric values are `<= maximum`. Strings/tables must have length `<= maximum`. |
| `Range` | `Range(minimum: number, maximum: number)` | Size is within `[minimum, maximum]`. Rejects values without a measurable size. |
| `Pattern` | `Pattern(pattern: string)` | Strings match the Lua pattern provided. Non-string values automatically fail. |
| `Enum` | `Enum(values: {any})` | Value equals one of the provided constants. |
| `Custom` | `Custom(predicate: (any) -> boolean)` | Runs a custom Luau function; success requires a truthy result. |
| `InstanceOf` | `InstanceOf(class: {})` | Value has the same metatable (or prototype chain) as the supplied class table. |
| `HasKey` | `HasKey(key: string)` | Tables expose the specified key with a non-`nil` value. |
| `HasKeys` | `HasKeys(keys: {string})` | Tables expose every key in the provided list. |
| `Schema` | `Schema(schema: {[string]: (any) -> boolean})` | Tables satisfy a schema made of per-key validator functions. |

### Executing validation
`Validate() -> (any, boolean, {string})`
- Runs all attached validators.
- Returns the original value when valid. Returns the default fallback (if provided) when invalid.

`GetErrors() -> {string}`
- Returns the array of error messages accumulated during the last `Validate()` call.

### Batch validation
`SafeValue.ValidateAll(safeValues: {SafeValueClass}) -> ({[string]: {IsValid: boolean, Value: any, Errors: {string}}}, boolean)`
 - Accepts a list or dictionary of `SafeValue` instances.
 - Returns a table keyed by each instance's `Name` (or positional fallback) containing the sanitized value, validity flag, and a copy of the error list.
 - Returns a second boolean indicating whether every instance succeeded.

## Usage Examples

### Enumerations and patterns
```lua
local username = SafeValue("player123", "guest", "Username")
    :Type({"string"})
    :Pattern("^%a[%w_]+$")

local status = SafeValue("moderator", "player", "Status")
    :Enum({"player", "builder", "moderator"})

local sanitizedUsername = username:Validate()
local sanitizedStatus = status:Validate()
```

### Complex table validation
```lua
local profileSchema = {
    id = function(value)
        local _, isValid = SafeValue(value)
            :Type({"string"})
            :Min(1)
            :Validate()
        return isValid
    end,
    level = function(value)
        local _, isValid = SafeValue(value)
            :Type({"number"})
            :Min(1)
            :Validate()
        return isValid
    end,
}

local profile = SafeValue({id = "abc123", level = 5}, nil, "Profile")
    :Type({"table"})
    :Schema(profileSchema)

local inventory = SafeValue({coins = 50, gems = 3}, {coins = 0, gems = 0}, "Inventory")
    :HasKeys({"coins", "gems"})

local hasOwner = SafeValue({owner = "Player1"}, {owner = "Unknown"}, "Ownership")
    :HasKey("owner")

local results, allValid = SafeValue.ValidateAll({profile, inventory, hasOwner})
if not allValid then
    for name, result in pairs(results) do
        if not result.IsValid then
            warn(name .. " failed validation")
            for _, err in ipairs(result.Errors) do
                warn("- " .. err)
            end
        end
    end
end
```

### Custom predicates
```lua
local evenNumber = SafeValue(12, 0, "EvenNumber")
    :Custom(function(value)
        return type(value) == "number" and value % 2 == 0
    end)

local value, isValid = evenNumber:Validate()
```

## Contributing
- File issues or improvement ideas in your preferred tracker.
- Please include reproduction steps for bugs and ensure tests continue to pass after changes.

## License
MIT License
