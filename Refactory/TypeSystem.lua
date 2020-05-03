
--[[

定义一个类型：
XXX = typesys.XXX {
	__pool_capacity = -1, 	-- 对象池容量，负数为无限
	__strong_pool = false,	-- 对象池是否使用强引用
	__super = typesys.YYY, 	-- 父类
	i = 0, 					-- 定义number型字段i
	str = "", 				-- 定义string型字段str
	b = false,				-- 定义boolean型字段b
	x = typesys.XXX,		-- 定义类型为A的字段x，此字段将强引用A类型对象，其生命周期由x托管
	weak_x1 = typesys.XXX,   -- 定义类型为A的字段x1，此字段将弱引用A类型对象，弱引用字段使用weak_前缀，请注意：字段名是不包含weak_前缀的
	
	_i = 0,					-- 定义number型私有字段_i
	_str = "", 				-- 定义string型私有字段_str
	_b = false,				-- 定义boolean型私有字段_b
	_x = typesys.XXX,		-- 定义类型为A的私有字段_x，此字段将强引用A类型对象，其生命周期由_x托管
	weak__x1 = typesys.XXX,   -- 定义类型为A的私有字段_x1，此字段将弱引用A类型对象，弱引用字段使用weak_前缀，请注意：字段名是不包含weak_前缀的

	c = typesys.__unmanaged,-- 定义非托管的字段c
}

function XXX:__ctor(...) end -- 类实例化对象的构造函数，创建或重用时被调用
function XXX:__dtor(...) end -- 类实例化对象的析构函数，销毁或回收时被调用

function XXX:foo(...) end 	-- 自定义实例化对象的函数

实例化对象访问自身的类型：
self.__type

调用父类函数：
XXX.__super.__ctor(self, ...)
XXX.__super.__dtor(self, ...)
XXX.__super.foo(self, ...)
或
self.__type.__super.__ctor(self, ...)
self.__type.__super.__dtor(self, ...)
self.__type.__super.foo(self, ...)

注意：
__双下划线前缀由系统保留，自定义请勿使用
_下划线前水为私有字段，私有字段，私有函数，只能由实例化对象自身进行调用

--]]

local _CHECK_MODE = true -- 启动强制检查机制，及时发现代码问题，但会有运行性能损耗

local assert = assert
local print = print

-- 辅助函数
local function _copyTable(to, from)
	for k, v in pairs(from) do
		to[k] = v
	end
end
local function _poolPush(pool, obj)
	pool[#pool+1] = obj
end
local function _poolPop(pool)
	local n = #pool
	if 0 < n then
		local e = pool[n]
		pool[n] = nil
		return e
	end
	return nil
end

typesys = {__unmanaged = {}}

-- 各类metatable
local _weak_pool_mt = {__mode = "kv"} 	-- 用于弱引用的对象池
local _type_def_mt = {} 				-- 用于类型定义语法糖
local _type_mt = {} 					-- 用于类型
local _obj_mt = {} 						-- 用于实例对象

-- 系统用到的辅助table
local _type_info_map = {} -- 类型信息映射表，type为键，info为值
local _INVALID_ID = 0
local _last_id = _INVALID_ID 
local _alive_objects = {} -- 存活的实例对象映射表，id为键，obj为值

local function _genObjID()
	_last_id = _last_id + 1
	return _last_id
end
local function _getObjectByID(id)
	return _alive_objects[id]
end

-- 用于类型的辅助函数
local function _type_getName(t)
	return t.__type_name
end
local function _type_isType(t1, t2)
	local info = _type_info_map[t1]
	local t = t1
	while nil ~= t do
		if t == t2 then
			return true
		end
		t = t.__super
	end
	return false
end

-- 用于对象的辅助函数
local function _obj_setID(obj, id)
	obj.__id = id
end
local function _obj_getID(obj)
	return obj.__id
end
local function _obj_hasOwner(obj)
	return obj.__owner or false
end
local function _obj_setOwner(obj, owner)
	obj.__owner = owner.__id
end
local function _obj_clearOwner(obj)
	obj.__owner = false
end
local function _obj_getOwner(obj)
	if obj.__owner then
		return _alive_objects[obj.__owner]
	end
	return nil
end
local function _obj_getType(obj)
	return obj.__type
end
local function _obj_isType(obj, t)
	return _type_isType(_obj_getType(obj), t)
end

local function _obj_create(t, info)
	local refs = nil
	if nil ~= next(info.ref) or nil ~= next(info.w_ref) then
		-- 创建引用表，用于放置被引用的字段对象，默认用false占位
		refs = {}
		for k in pairs(info.ref) do
			refs[k] = false
		end
		for k in pairs(info.w_ref) do
			refs[k] = false
		end
	end
	return {__type = t, __id = _INVALID_ID, __refs = refs, __owner = false}
end
local function _obj_alive(obj, id, t, info, ...)
	_obj_setID(obj, id)
	
	local not_refs = obj
	if _CHECK_MODE then
		if nil == obj.__not_refs then
			obj.__not_refs = {}
		end
		not_refs = obj.__not_refs
	end
	-- 将值类型字段的缺省值赋值给对象
	for k,v in pairs(info.num) do
		rawset(not_refs, k, v)
	end
	for k,v in pairs(info.str) do
		rawset(not_refs, k, v)
	end
	for k,v in pairs(info.bool) do
		rawset(not_refs, k, v)
	end
	
	setmetatable(obj, _obj_mt)

	-- 将对象放入映射表中
	_alive_objects[id] = obj

	-- 调用对象的构造函数
	if nil ~= t.__ctor then
		t.__ctor(obj, ...)
	end
end
local function _obj_die(obj, t, info)
	local id = obj.__id
	obj.__id = _INVALID_ID

	_alive_objects[id] = nil

	if nil ~= t.__dtor then
		t.__dtor(obj)
	end

	setmetatable(obj, nil)
end

-- 用于值的辅助函数
local function _v_getTypeName(v)
	local type_name = type(v)
	if "table" == type_name then
		local t = _obj_getType(v)
		if nil ~= t then
			return _type_getName(t)
		end
	end
	return type_name
end

_type_mt.__index = rawget
_type_mt.__newindex = rawset

_obj_mt.__index = function(obj, field_name)
	local t = obj.__type
	local info = _type_info_map[t]

	-- 1. 非托管字段
	if nil ~= info.unmanaged[field_name] then
		return nil
	end

	-- 2. 非引用类型字段
	local not_refs = obj.__not_refs
	if nil ~= not_refs then
		local v = not_refs[field_name]
		if nil ~= v then
			return v
		end
	end

	-- 3. 对象的引用类型字段
	local ref = info.ref[field_name]
	if nil ~= ref then
		-- 强引用，直接返回引用的对象
		return obj.__refs[field_name] or nil
	end
	ref = info.w_ref[field_name]
	if nil ~= ref then
		-- 弱引用，通过引用的ID查找引用的对象
		local ref_id = obj.__refs[field_name]
		if ref_id then
			return _alive_objects[ref_id]
		end
		return nil
	end

	-- 4. 类型字段（一般指函数，或静态变量）
	local tv = t[field_name]
	if nil ~= tv then
		return tv
	end

	-- 5.
	assert(false, string.format("<字段获取错误> 字段不存在：%s.%s", t.__type_name, field_name))
end
_obj_mt.__newindex = function(obj, field_name, v)
	local t = obj.__type
	local info = _type_info_map[t]

	-- 1. 非托管字段
	if nil ~= info.unmanaged[field_name] then
		rawset(obj, field_name, v)
		return
	end

	-- 2. 非引用类型字段
	local not_refs = obj.__not_refs
	if nil ~= not_refs and nil ~= not_refs[field_name] then
		if nil ~= info.num[field_name] then
			assert("number" == type(v), string.format("<字段赋值错误> 类型不匹配：%s.%s(number)，值类型为：%s", t.__type_name, field_name, _v_getTypeName(v)))
			not_refs[field_name] = v
		elseif nil ~= info.str[field_name] then
			assert("string" == type(v), string.format("<字段赋值错误> 类型不匹配：%s.%s(string)，值类型为：%s", t.__type_name, field_name, _v_getTypeName(v)))
			not_refs[field_name] = v
		elseif nil ~= info.bool[field_name] then
			assert("boolean" == type(v), string.format("<字段赋值错误> 类型不匹配：%s.%s(boolean)，值类型为：%s", t.__type_name, field_name, _v_getTypeName(v)))
			not_refs[field_name] = v
		end
		return
	end

	-- 3. 对象的引用类型字段
	local rt = info.ref[field_name]
	if nil ~= rt then
		-- 强引用类型字段
		if nil ~= v then
			assert(not _obj_hasOwner(v), string.format("<字段赋值错误> 值已经被其他所有者持有：%s.%s(number)，持有者类型为：%s", t.__type_name, field_name, _obj_getOwner(v).__type))
			assert(_obj_isType(v, rt), string.format("<字段赋值错误> 类型不匹配：%s.%s(%s)，值类型为：%s", t.__type_name, field_name, _type_getName(rt), _v_getTypeName(v)))
			_obj_setOwner(v, obj)
		else
			-- 如果赋值为nil，那么使用false作为占位值
			v = false
		end

		local old = obj.__refs[field_name]
		obj.__refs[field_name] = v

		if old then
			-- 销毁原持有的对象
			_obj_clearOwner(old)
			typesys.delete(old)
		end
		return
	end
	rt = info.w_ref[field_name]
	if nil ~= rt then
		-- 弱引用类型字段
		if nil ~= v then
			assert(_obj_isType(v, rt), string.format("<字段赋值错误> 类型不匹配：%s.%s(%s)，值类型为：%s", t.__type_name, field_name, _type_getName(rt), _v_getTypeName(v)))
			v = _obj_getID(v)
		else
			-- 如果赋值为nil，那么使用false作为占位值
			v = false
		end

		obj.__refs[field_name] = v
		return
	end

	-- 4. 类型字段
	assert(nil == t[field_name], string.format("<字段赋值错误> 不允许用对象为类字段赋值：%s.%s", t.__type_name, field_name))

	-- 5.
	assert(false, string.format("<字段赋值错误> 字段不存在：%s.%s", t.__type_name, field_name))
end

-- 类型定义语法糖，用于实现typesys.XXX {}语法
-- 此语法可以将{}作为proto传递给__call函数
_type_def_mt.__call = function(t, proto)
	assert(nil == _type_info_map[t], "<类型定义错误> 重复定义类型："..t.__type_name)

	print("\n------定义类型开始：", t.__type_name, "--------")

	local info = {
		pool_capacity = -1,
		strong_pool = false,
		super = nil,
		pool = {}, -- 对象池
		-- 各类型字段查询表
		num = {},
		str = {},
		bool = {},
		ref = {},
		w_ref = {},
		unmanaged = {},
	}

	if nil ~= proto.__super then
		local super = proto.__super
		info.super = super
		local super_info = _type_info_map[super]
		assert(nil ~= super_info, "<类型定义错误> 父类未定义")

		-- 将父类的字段查询表拷贝过来
		_copyTable(info.num, super_info.num)
		_copyTable(info.str, super_info.str)
		_copyTable(info.bool, super_info.bool)
		_copyTable(info.ref, super_info.ref)
		_copyTable(info.w_ref, super_info.w_ref)
		_copyTable(info.unmanaged, super_info.unmanaged)

		t.__super = super
		local mt = {}
		_copyTable(mt, _type_mt)
		mt.__index = super
		setmetatable(t, mt)
	else
		setmetatable(t, _type_mt)
	end

	-- 解析协议
	for field_name, v in pairs(proto) do
		assert(type(field_name) == "string", "<类型定义错误> 字段名不是字符串类型")

		if "__pool_capacity" == field_name then
			assert("number" == type(v), "<类型定义错误> __pool_capacity的值不是number类型")
			print("对象池容量：", v)
			info.pool_capacity = v
		elseif "__strong_pool" == field_name then
			assert("boolean" == type(v), "<类型定义错误> __strong_pool的值不是boolean类型")
			print("对象池是否使用强引用：", v)
			info.strong_pool = v
		elseif "__super" == field_name then
		else
			assert("__" ~= string.sub(field_name, 1, 2), "<类型定义错误> “__”为系统保留前缀，不允许使用："..field_name)
			if typesys.__unmanaged == v then
				print("非托管字段：", field_name)
				info.unmanaged[field_name] = false -- false作为slot占位
			else
				local vt = type(v)
				if "number" == vt then
					info.num[field_name] = v
					print("number类型字段：", field_name, "缺省值：", v)
				elseif "string" == vt then
					info.str[field_name] = v
					print("string类型字段：", field_name, "缺省值：", v)
				elseif "boolean" == vt  then
					info.bool[field_name] = v
					print("boolean类型字段：", field_name, "缺省值：", v)
				elseif vt == "table" and nil ~= typesys[_type_getName(v)] then
					-- 引用类型
					local weak_field_name = field_name:match("^weak_(.+)")
					if weak_field_name then
						assert(nil == proto[weak_field_name], "<类型定义错误> 弱引用字段与其他字段重名："..field_name)
						
						field_name = weak_field_name
						info.w_ref[field_name] = v
						print("弱引用类型字段：", field_name, "=", _type_getName(v))
					else
						assert(nil == info.w_ref[field_name], "<类型定义错误> 强引用字段与弱引用字段重名："..field_name)
						info.ref[field_name] = v
						print("强引用类型字段：", field_name, "=", _type_getName(v))
					end
				else
					assert(false, "<类型定义错误> 字段值类型错误："..field_name)
				end
			end
		end
	end

	if not info.strong_pool then
		setmetatable(info.pool, _weak_pool_mt)
	end

	-- 将类型信息放入到映射表中
	_type_info_map[t] = info

	print("------类型定义结束：", t.__type_name, "--------\n")
	return t
end

function typesys.new(t, ...)
	local info = _type_info_map[t]
	assert(nil ~= info, "<new错误> 类型不存在")

	-- 1. 生成实例ID
	local id = _genObjID()

	-- 2. 尝试重用
	local obj = _poolPop(info.pool)
	if nil == obj then
		obj = _obj_create(t, info)
		print("<new> 新建：", _type_getName(t), id)
	else
		print("<new> 重用：", _type_getName(t), id)
	end
	
	-- 3. 使对象生效
	_obj_alive(obj, id, t, info, ...)
	return obj
end

function typesys.delete(obj)
	assert(not _obj_hasOwner(obj), "<delete错误> 对象仍然被持有，不允许delete")

	local id = _obj_getID(obj)
	assert(obj == _getObjectByID(id), "<delete错误> 对象不存在")

	local t = _obj_getType(obj)
	local info = _type_info_map[t]

	-- 1. 使对象失效
	_obj_die(obj, t, info)

	-- 2. 清除引用
	local refs = obj.__refs
	if nil ~= refs then
		for k, ref in pairs(refs) do
			refs[k] = false
			if ref and nil ~= info.ref[k] then
				-- 销毁强引用字段对象
				_obj_clearOwner(ref)
				typesys.delete(ref)
			end
		end
	end

	-- 3. 尝试回收
	local pool = info.pool
	local pool_size = #pool
	local pool_capacity = info.pool_capacity
	if 0 > pool_capacity or 0 ~= pool_capacity and pool_size < pool_capacity then
		-- 将对象回收并放入到对象池当中
		print("<delete> 回收：", _type_getName(t), id)
		_poolPush(pool, obj)
	else
		print("<delete> 销毁：", _type_getName(t), id)
	end
end

-- 类型定义语法糖，用于实现typesys.XXX语法
-- 此语法可以将XXX作为name传递给__index函数，而t就是typesys
setmetatable(typesys, {
	__index = function(t, name)
		assert(nil == rawget(t, name), "<类型定义错误> 类型名已存在："..name)
		local new_t = setmetatable({
			__type_name = name
		}, _type_def_mt)
		rawset(t, name, new_t)
		return new_t
	end
})