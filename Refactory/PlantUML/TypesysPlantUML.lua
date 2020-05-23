
local function _arrayPush(a, e)
	a[#a+1] = e
end

local function _fieldsExcludeInherit(fields, super_fields)
	local self_fields = {}
	for k, v in pairs(fields) do
		if nil == super_fields[k] then
			self_fields[k] = v
		end
	end
	return self_fields
end

local function _getSelfFields(type_info_map, t, fields_name)
	local super = t.__super
	if nil == super then
		return type_info_map[t][fields_name]
	end

	local info = type_info_map[t]
	local super_info = type_info_map[super]
	return _fieldsExcludeInherit(info[fields_name], super_info[fields_name])
end

local function _getFieldAuthority(field_name)
	if "_" == string.sub(field_name, 1, 1) then
		return "-"
	else
		return "+"
	end
end

local function _typeInfoToArray(type_info_map, t, a)
	a = a or {}

	_arrayPush(a, string.format("class %s {", t.__type_name))

	-- fields
	local num_fields = _getSelfFields(type_info_map, t, "num")
	for k, v in pairs(num_fields) do
		_arrayPush(a, string.format("%s%s : number | %d", _getFieldAuthority(k), k, v))
	end
	local str_fields = _getSelfFields(type_info_map, t, "str")
	for k, v in pairs(str_fields) do
		_arrayPush(a, string.format("%s%s : string | \"%s\"", _getFieldAuthority(k), k, v))
	end
	local bool_fields = _getSelfFields(type_info_map, t, "bool")
	for k, v in pairs(bool_fields) do
		_arrayPush(a, string.format("%s%s : boolean | %s", _getFieldAuthority(k), k, tostring(v)))
	end
	local ref_fields = _getSelfFields(type_info_map, t, "ref")
	for k, v in pairs(ref_fields) do
		_arrayPush(a, string.format("%s%s : %s", _getFieldAuthority(k), k, v.__type_name))
	end
	local w_ref_fields = _getSelfFields(type_info_map, t, "w_ref")
	for k, v in pairs(w_ref_fields) do
		_arrayPush(a, string.format("%s%s : %s[weak]", _getFieldAuthority(k), k, v.__type_name))
	end
	local unmanaged_fields = _getSelfFields(type_info_map, t, "unmanaged")
	for k, v in pairs(unmanaged_fields) do
		_arrayPush(a, string.format("%s%s : unmanaged", _getFieldAuthority(k), k))
	end

	-- functions & static
	for k, v in pairs(t) do
		local v_type = type(v)
		if "function" == v_type then
			_arrayPush(a, string.format("%s%s()", _getFieldAuthority(k), k))
		elseif "number" == v_type then
			_arrayPush(a, string.format("{static} %s%s : number | %d", _getFieldAuthority(k), k, v))
		elseif "string" == v_type then
			_arrayPush(a, string.format("{static} %s%s : string | \"%s\"", _getFieldAuthority(k), k, v))
		elseif "boolean" == v_type then
			_arrayPush(a, string.format("{static} %s%s : boolean | %s", _getFieldAuthority(k), k, tostring(v)))
		elseif "table" == v_type then
			local sys_type_info = type_info_map[v]
			if nil ~= sys_type_info then
				_arrayPush(a, string.format("{static} %s%s : %s", _getFieldAuthority(k), k, v.__type_name))
			else
				_arrayPush(a, string.format("{static} %s%s : table", _getFieldAuthority(k), k))
			end
		end
	end

	_arrayPush(a, "}")

	return a
end
local function _typeRelationshipToArray(type_info_map, t, a)
	a = a or {}

	local type_name = t.__type_name

	-- inherit
	if nil ~= t.__super then
		_arrayPush(a, string.format("%s <|-- %s ", t.__super.__type_name, type_name))
	end

	-- dependency
	local ref_fields = _getSelfFields(type_info_map, t, "ref")
	for k, v in pairs(ref_fields) do
		_arrayPush(a, string.format("%s --> %s", type_name, v.__type_name))
	end
	local w_ref_fields = _getSelfFields(type_info_map, t, "w_ref")
	for k, v in pairs(w_ref_fields) do
		_arrayPush(a, string.format("%s ..> %s : weak", type_name, v.__type_name))
	end

	return a
end

typesys.tools.toPlantUML = function(file_path)
	local file = io.open(file_path, "w")
	if nil == file then
	    return false
	end

	local text_array = {}
	_arrayPush(text_array, "@startuml")

	local type_info_map = typesys.__getAllTypesInfo()
	for t,_ in pairs(type_info_map) do
		_typeInfoToArray(type_info_map, t, text_array)
		_typeRelationshipToArray(type_info_map, t, text_array)
	end

	_arrayPush(text_array, "@enduml")

	file:write(table.concat(text_array, "\n"))

	file:close()
	return true
end



