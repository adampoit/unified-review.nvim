---@meta

---@class BustedAssertNamespace
---@field equal fun(expected:any, actual:any, message?:string)
---@field same fun(expected:any, actual:any, message?:string)

---@class BustedAssert
---@field are BustedAssertNamespace
---@field is_nil fun(actual:any, message?:string)
---@field is_not_nil fun(actual:any, message?:string)
---@field is_true fun(actual:any, message?:string)
---@field is_false fun(actual:any, message?:string)
---@field is_string fun(actual:any, message?:string)
---@field is_not_equal fun(expected:any, actual:any, message?:string)
---@field matches fun(pattern:string, actual:string, message?:string)
---@field not_matches fun(pattern:string, actual:string, message?:string)
---@field has_error fun(fn:function, expected?:string)
---@field stub fun(target:table, key:string, replacement?:function)
---@field spy fun(target:table, key:string)

---@type BustedAssert|fun(value:any, message?:string): any
assert = nil

describe = nil
it = nil
before_each = nil
after_each = nil
pending = nil
stub = nil
spy = nil
