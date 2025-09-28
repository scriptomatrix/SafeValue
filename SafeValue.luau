--[=[
    SafeValue — Fluent validation helper for Roblox Luau projects.

    Wrap raw values in a `SafeValue` instance to chain validators like `Type`,
    `Range`, or `Schema`. Call `Validate()` to retrieve the sanitized value,
    validity flag, and error messages, or use `SafeValue.ValidateAll` to process
    many wrapped values at once.

    ## Quick example
    ```lua
    local SafeValue = require(path.To.SafeValue)

    local health = SafeValue(100, 50, "Health")
        :Type({"number"})
        :Range(0, 200)

    local value, isValid, errors = health:Validate()
    ```
]=]

--!strict

export type ValidationData = {
    type: string?,
    default: any?,
    min: number?,
}

--[=[
    Computes a numeric size for numbers, strings, and tables; returns nil for
    unsupported types.

    @param value any
    @return number? size
]=]
local function getSize(value: any): number?
    if type(value) == "number" then
        return value
    elseif type(value) == "string" then
        return #value
    elseif type(value) == "table" then
        return #value
    end
    return nil
end

--[=[
    Canonical keys for every validator SafeValue exposes. Used internally to
    register and execute validators.
]=]
local EnumValidators = {
    Type = "type",
    Min = "Min",
    Max = "Max",
    Range = "Range",
    Pattern = "Pattern",
    Enum = "Enum",
    Custom = "Custom",
    InstanceOf = "InstanceOf",
    HasKey = "HasKey",
    HasKeys = "HasKeys",
    Schema = "Schema",
}

--[=[
    Validator dispatch table mapping names to predicate implementations.

    Each entry receives the raw `value` and its validator configuration table
    and returns a boolean indicating validity.
]=]
local validatorFunctions = {
    [EnumValidators.Type] = function(value: any, validator: any): boolean
        -- Validate that the value matches one of the specified types
        local Types = validator.Types

        for _, Type in pairs(Types) do
            if type(value) == Type then
                return true
            end
        end
        return false
    end,

    [EnumValidators.Min] = function(value: any, validator: any): boolean
        -- Validate that the value's size is greater than or equal to the minimum
        local size = getSize(value)
        if size and size < validator.Value then
            return false
        end
        return true
    end,

    [EnumValidators.Max] = function(value: any, validator: any): boolean
        -- Validate that the value's size is less than or equal to the maximum
        local size = getSize(value)
        if size and size > validator.Value then
            return false
        end
        return true
    end,

    [EnumValidators.Range] = function(value: any, validator: any): boolean
        -- Validate that the value's size is within a specified range
        local min = validator.min
        local max = validator.max
        local size = getSize(value)
        
        if not size then return false end
        return size >= min and size <= max
    end,


    [EnumValidators.Pattern] = function(value: any, validator: any): boolean
        -- Validate that the value matches a specified regex pattern
        if type(value) ~= "string" then return false end
        
        local pattern = validator.pattern
        return string.match(value, pattern) ~= nil
    end,

    [EnumValidators.Enum] = function(value: any, validator: any): boolean
        -- Validate that the value is one of the allowed enum values
        local allowedValues = validator.values
        
        for _, allowedValue in pairs(allowedValues) do
            if value == allowedValue then
                return true
            end
        end
        return false
    end,

    [EnumValidators.Custom] = function(value: any, validator: any): boolean
        -- Validate using a custom function
        local customFunction = validator.customFunction
        if type(customFunction) ~= "function" then return false end
        
        return customFunction(value)
    end,


    -- Advanced Validators
    [EnumValidators.InstanceOf] = function(value: any, validator: any): boolean
        -- Validate that value is an instance of a specific class
        local class = validator.class
        if type(class) ~= "table" then return false end
        
        -- Check if value is an instance by looking for class-specific methods or properties
        if type(value) ~= "table" then return false end
        
        -- Simple instance check - value should have the same metatable or inherit from class
        local valueMt = getmetatable(value)
        if valueMt == class then return true end
        
        -- Check inheritance chain
        local visited = {}
        while valueMt do
            if valueMt == class then return true end
            if visited[valueMt] then break end
            visited[valueMt] = true
            valueMt = valueMt.__index
        end
        
        return false
    end,

    [EnumValidators.HasKey] = function(value: any, validator: any): boolean
        -- Validate that table has a specific key
        if type(value) ~= "table" then return false end
        
        local key = validator.key
        return value[key] ~= nil
    end,

    [EnumValidators.HasKeys] = function(value: any, validator: any): boolean
        -- Validate that table has all specified keys
        if type(value) ~= "table" then return false end
        
        local keys = validator.keys
        if type(keys) ~= "table" then return false end
        
        for _, key in pairs(keys) do
            if value[key] == nil then
                return false
            end
        end
        return true
    end,

    [EnumValidators.Schema] = function(value: any, validator: any): boolean
        -- Validate that table matches a schema structure
        if type(value) ~= "table" then return false end
        
        local schema = validator.schema
        if type(schema) ~= "table" then return false end
        
        -- Check each key in schema
        for key, schemaValidator in pairs(schema) do
            if value[key] == nil then
                return false
            end
            
            -- If schemaValidator is a function, use it to validate the value
            if type(schemaValidator) == "function" then
                if not schemaValidator(value[key]) then
                    return false
                end
            end
        end
        return true
    end,
}

--[=[
    Metatable implementing fluent SafeValue behaviour. Instances created via
    `SafeValue(value)` delegate methods to this table.
]=]
local safeValue = {}
safeValue.__index = safeValue

export type SafeValueClass = typeof(safeValue)

--[=[
    Constructs a new SafeValue instance that wraps the provided value and
    optional fallback/default.

    @generic T
    @param value T -- The value to validate.
    @param DefaultValue T? -- Optional fallback returned when validation fails.
    @param valueName string -- Optional label used by `ValidateAll`.
    @return SafeValueClass

    @example
    ```lua
    local position = SafeValue(Vector3.new(), Vector3.zero, "Position")
    ```
]=]
function safeValue:__call<T>(value: T, DefaultValue: T?, valueName: string)
    -- Create new instance with metatable
    self = setmetatable({}, safeValue)
    
    -- Initialize instance properties
    self.Name = valueName or ""
    self.__IsValid = true
    self.__Value = value
    self.__DefaultValue = DefaultValue
    self.__IsNullable = false
    self.__ValidationData = {} :: ValidationData
    self.__ErrorsList = {}
    
    return self
end

--[=[
    Appends a formatted validation error message to the instance list.

    @param text string -- A human-friendly description of the validation failure.
]=]
function safeValue:__addError(text: string)
    local errorMessage = `value is {text}`
    table.insert(self.__ErrorsList, errorMessage)
end

--[=[
    Registers or overrides a validator configuration on this instance.

    @param validatorName string -- Key from `EnumValidators`.
    @param data {} -- Validator-specific configuration.
]=]
function safeValue:__addValidator(validatorName: string, data: {})
    if self.__ValidationData[validatorName] then
        warn(`({validatorName}) validator is already defined, now it will be redefined`)
    end
    self.__ValidationData[validatorName] = data
end

--[=[
    Requires the wrapped value to match at least one Luau type provided in
    `Types`.

    @param Types {string} -- Acceptable Luau type strings (e.g. "string").
    @return SafeValueClass

    @example
    ```lua
    SafeValue("Guest"):Type({"string", "nil"})
    ```
]=]
function safeValue:Type(Types: {string}): SafeValueClass
    self:__addValidator(EnumValidators.Type, {Types = Types})
    return self
end

--[=[
    Enforces a minimum numeric value or, for strings/tables, minimum length.

    @param value number -- The inclusive lower bound.
    @return SafeValueClass

    @example
    ```lua
    SafeValue(#playerList)
        :Min(1)
    ```
]=]
function safeValue:Min(value: number): SafeValueClass
    self:__addValidator(EnumValidators.Min, {Value = value})
    return self
end

--[=[
    Enforces a maximum numeric value or, for strings/tables, maximum length.

    @param value number -- The inclusive upper bound.
    @return SafeValueClass

    @example
    ```lua
    SafeValue(health):Max(200)
    ```
]=]
function safeValue:Max(value: number): SafeValueClass
    self:__addValidator(EnumValidators.Max, {Value = value})
    return self
end

--[=[
    Constrains the value to lie within an inclusive numeric range or length.

    @param min number
    @param max number
    @return SafeValueClass

    @example
    ```lua
    SafeValue(temperature):Range(-10, 60)
    ```
]=]
function safeValue:Range(min: number, max: number): SafeValueClass
    self:__addValidator(EnumValidators.Range, {min = min, max = max})
    return self
end


--[=[
    Requires string values to match the supplied Lua pattern.

    @param pattern string -- Lua pattern the value must satisfy.
    @return SafeValueClass

    @example
    ```lua
    SafeValue(username)
        :Pattern("^%a[%w_]+$")
    ```
]=]
function safeValue:Pattern(pattern: string): SafeValueClass
    self:__addValidator(EnumValidators.Pattern, {pattern = pattern})
    return self
end

--[=[
    Restricts the value to one of the allowed entries.

    @param values {any}
    @return SafeValueClass

    @example
    ```lua
    SafeValue(status):Enum({"player", "moderator", "admin"})
    ```
]=]
function safeValue:Enum(values: {any}): SafeValueClass
    self:__addValidator(EnumValidators.Enum, {values = values})
    return self
end

--[=[
    Applies a user-provided predicate to determine validity.

    @param customFunction (any) -> boolean -- Function returning true when valid.
    @return SafeValueClass

    @example
    ```lua
    SafeValue(score)
        :Custom(function(value)
            return value % 2 == 0
        end)
    ```
]=]
function safeValue:Custom(customFunction: (any) -> boolean): SafeValueClass
    self:__addValidator(EnumValidators.Custom, {customFunction = customFunction})
    return self
end


-- Advanced Validators
--[=[
    Validates that the value shares a metatable lineage with `class`.

    @param class {}
    @return SafeValueClass

    @example
    ```lua
    SafeValue(instance):InstanceOf(BaseComponent)
    ```
]=]
function safeValue:InstanceOf(class: {}): SafeValueClass
    self:__addValidator(EnumValidators.InstanceOf, {class = class})
    return self
end

--[=[
    Requires the wrapped table to contain the specified key with a non-nil value.

    @param key string
    @return SafeValueClass

    @example
    ```lua
    SafeValue(profile):HasKey("id")
    ```
]=]
function safeValue:HasKey(key: string): SafeValueClass
    self:__addValidator(EnumValidators.HasKey, {key = key})
    return self
end

--[=[
    Requires the wrapped table to contain every key in `keys`.

    @param keys {string}
    @return SafeValueClass

    @example
    ```lua
    SafeValue(settings)
        :HasKeys({"theme", "language"})
    ```
]=]
function safeValue:HasKeys(keys: {string}): SafeValueClass
    self:__addValidator(EnumValidators.HasKeys, {keys = keys})
    return self
end

--[=[
    Validates the wrapped table using per-key predicate functions.

    @param schema {[string]: (any) -> boolean} -- Functions returning true per key.
    @return SafeValueClass

    @example
    ```lua
    SafeValue(playerInfo)
        :Schema({
            name = function(v)
                lcoal _, isValid = SafeValue(v):Type({"string"}):Validate()
                return isValid
            end,
        })
    ```
]=]
function safeValue:Schema(schema: {[string]: (any) -> boolean}): SafeValueClass
    self:__addValidator(EnumValidators.Schema, {schema = schema})
    return self
end

--[=[
    Runs all configured validators and returns the sanitized value, a validity
    flag, and copied error messages.

    @return any value -- Either the original value or fallback.
    @return boolean isValid
    @return {string} errors

    @example
    ```lua
    local value, isValid, errors = SafeValue(health, 0)
        :Min(0)
        :Validate()
    ```
]=]
function safeValue:Validate(): (any, boolean, {string})
    -- Run all validators
    self.__IsValid = true
    self.__ErrorsList = {}

    for validatorName, validatorData in pairs(self.__ValidationData) do
        local validatorFunction = validatorFunctions[validatorName]
        local isValid = validatorFunction(self.__Value, validatorData)
        if not isValid then 
            self.__IsValid = false
            -- Add specific error message based on validator type
            self:__addValidatorError(validatorName, validatorData)
        end
    end

    -- Determine the return value
    local returnValue = self.__Value
    if not self.__IsValid and self.__DefaultValue then
        returnValue = self.__DefaultValue
    end

    local errors = table.clone(self.__ErrorsList)
    return returnValue, self.__IsValid, errors
end

--[=[
    Builds an error message for the most recent validator failure by inspecting
    the validator configuration.

    @param validatorName string
    @param validatorData {}
]=]
function safeValue:__addValidatorError(validatorName: string, validatorData: {})
    if validatorName == EnumValidators.Type then
        local types = table.concat(validatorData.Types, ", ")
        self:__addError(`not one of the allowed types: {types}`)
    elseif validatorName == EnumValidators.Min then
        self:__addError(`less than minimum value of {validatorData.Value}`)
    elseif validatorName == EnumValidators.Max then
        self:__addError(`greater than maximum value of {validatorData.Value}`)
    elseif validatorName == EnumValidators.Range then
        self:__addError(`not within range {validatorData.min} to {validatorData.max}`)
    elseif validatorName == EnumValidators.Pattern then
        self:__addError(`does not match required pattern: {validatorData.pattern}`)
    elseif validatorName == EnumValidators.Enum then
        local values = table.concat(validatorData.values, ", ")
        self:__addError(`not one of the allowed values: {values}`)
    elseif validatorName == EnumValidators.Custom then
        self:__addError("failed custom validation")
    -- Advanced Validators
    elseif validatorName == EnumValidators.InstanceOf then
        self:__addError("not an instance of the required class")
    elseif validatorName == EnumValidators.HasKey then
        self:__addError(`missing required key: {validatorData.key}`)
    elseif validatorName == EnumValidators.HasKeys then
        local keys = table.concat(validatorData.keys, ", ")
        self:__addError(`missing required keys: {keys}`)
    elseif validatorName == EnumValidators.Schema then
        self:__addError("does not match required schema structure")
    end
end

--[=[
    Returns the errors produced during the last `Validate()` call. Mutating the
    returned table does not impact internal state.

    @return {string}
]=]
function safeValue:GetErrors()
    return self.__ErrorsList
end

--[=[
    Validates a collection of SafeValue instances and aggregates the results in
    a table keyed by each instance's `Name`.

    @param safeValues {}
    @return {[string]: {IsValid: boolean, Value: any, Errors: {string}}} results
    @return boolean overallIsValid

    @example
    ```lua
    local results, allValid = SafeValue.ValidateAll({health, stamina})
    ```
]=]
function safeValue.ValidateAll(safeValues: {}): ({[string]: {IsValid: boolean, Value: any, Errors: {string}}}, boolean)
    local results = {}
    local overallIsValid = true
    
    for index, safeValueInstance in pairs(safeValues) do
        -- Validate each SafeValue instance
        local value, isValid, errors = safeValueInstance:Validate()
        
        -- Track overall validity
        if not isValid then 
            overallIsValid = false 
        end
        
        -- Create result data
        local resultData = {
            Value = value,
            IsValid = isValid,
            Errors = errors,
        }
        
        -- Use the SafeValue's name or generate one
        local name = safeValueInstance.Name or "value" .. tostring(index)
        results[name] = resultData
    end

    return results, overallIsValid
end

--[=[
    Internal metatable backing the callable SafeValue constructor. Not exported
    directly; instead exposed through the module return value.
]=]
local meta = setmetatable({}, safeValue)

local publicMeta = {}
publicMeta.__index = publicMeta

function publicMeta:__call(value: any, defaultValue: any, valueName: string?): SafeValueClass
    return meta(value, defaultValue, valueName)
end

--[=[
    Public helper mirroring `safeValue.ValidateAll` for batch workflows.

    @param safeValues {}
    @return {[string]: {IsValid: boolean, Value: any, Errors: {string}}}, boolean
]=]
function publicMeta.ValidateAll(safeValues: {}): ({[string]: {IsValid: boolean, Value: any, Errors: {string}}}, boolean)
    return meta.ValidateAll(safeValues)
end

return setmetatable({}, publicMeta)
