package tea;

import ex.*;

import haxe.Exception;
import haxe.Timer;

import teaBase.*;
import teaBase.Expr;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import tea.backend.*;
import tea.backend.TeaPreset.TeaPresetMode;

using StringTools;

typedef Tea =
{
	#if sys
	public var ?fileName(default, null):String;
	#end
	
	public var succeeded(default, null):Bool;

	public var calledFunction(default, null):String;

	public var returnValue(default, null):Null<Dynamic>;

	public var exceptions(default, null):Array<TeaException>;

	public var lastReportedTime(default, null):Float;
}

@:structInit
@:access(tea.backend.TeaPreset)
@:access(teaBase.Interp)
@:access(teaBase.Parser)
@:access(teaBase.Tools)
@:access(llua.Interp3LL)
@:keepSub
class SScript
{
	public static var defaultImprovedField(default, set):Null<Bool> = true;

	public static var defaultTypeCheck(default, set):Null<Bool> = true;

	public static var defaultDebug(default, set):Null<Bool> = null;

	public static var defaultTeaPreset:TeaPresetMode = MINI;

	public static var globalVariables:TeaGlobalMap = new TeaGlobalMap();

	public static var global(default, null):Map<String, SScript> = [];

	public static var defaultFun(default, set):String = "main";
	
	static var IDCount(default, null):Int = 0;

	static var BlankReg(get, never):EReg;

	static var classReg(get, never):EReg;
	
	public var defaultFunc:String = null;

	public var improvedField(default, set):Null<Bool> = true;

	public var customOrigin(default, set):String;

	public var returnValue(default, null):Null<Dynamic>;

	public var ID(default, null):Null<Int> = null;

	public var typeCheck:Bool = false;

	public var lastReportedTime(default, null):Float = -1;

	public var notAllowedClasses(default, null):Array<Class<Dynamic>> = [];

	public var presetter(default, null):TeaPreset;

	public var variables(get, never):Map<String, Dynamic>;

	public var interp(default, null):Interp;

	public var parser(default, null):Parser;

	public var script(default, null):String = "";

	public var active:Bool = true;

	public var scriptFile(default, null):String = "";

	public var traces:Bool = false;

	public var debugTraces:Bool = false;

	public var parsingException(default, null):TeaException;

	public var classPath(get, null):String;

	public var packagePath(get, null):String = "";

	@:noPrivateAccess var _destroyed(default, null):Bool;

	public function new(?scriptPath:String = "", ?preset:Bool = true, ?startExecute:Bool = true)
	{
		var time = Timer.stamp();

		if (defaultTypeCheck != null)
			typeCheck = defaultTypeCheck;
		if (defaultDebug != null)
			debugTraces = defaultDebug;
		if (defaultFun != null)
			defaultFunc = defaultFun;

		interp = new Interp();
		interp.setScr(this);
		
		if (defaultImprovedField != null)
			improvedField = defaultImprovedField;
		else 
			improvedField = improvedField;

		parser = new Parser();

		presetter = new TeaPreset(this);
		if (preset)
			this.preset();

		for (i => k in globalVariables)
		{
			if (i != null)
				set(i, k, true);
		}

		try 
		{
			doFile(scriptPath);
			if (startExecute)
				execute();
			lastReportedTime = Timer.stamp() - time;

			if (debugTraces && scriptPath != null && scriptPath.length > 0)
			{
				if (lastReportedTime == 0)
					trace('Tea brewed instantly (0 seconds)');
				else 
					trace('Tea brewed in ${lastReportedTime} seconds');
			}
		}
		catch (e)
		{
			lastReportedTime = -1;
		}
	}

	public function execute():Void
	{
		if (_destroyed || !active)
			return;

		parsingException = null;

		var origin:String = {
			if (customOrigin != null && customOrigin.length > 0)
				customOrigin;
			else if (scriptFile != null && scriptFile.length > 0)
				scriptFile;
			else 
				"SScript";
		};

		if (script != null && script.length > 0)
		{
			resetInterp();

			function tryHaxe()
			{
				try 
				{
					var expr:Expr = parser.parseString(script, origin);
					var r = interp.execute(expr);
					returnValue = r;
				}
				catch (e) 
				{
					parsingException = e;				
					returnValue = null;
				}
				
				if (defaultFunc != null)
					call(defaultFunc);
			}
			
			tryHaxe();
		}
	}

	public function set(key:String, ?obj:Dynamic, ?setAsFinal:Bool = false):SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return this;
		
		if (key == null || BlankReg.match(key) || !classReg.match(key))
			throw '$key is not a valid class name';
		else if (obj != null && (obj is Class) && notAllowedClasses.contains(obj))
			throw 'Tried to set ${Type.getClassName(obj)} which is not allowed';
		else if (Tools.keys.contains(key))
			throw '$key is a keyword and cannot be replaced';

		function setVar(key:String, obj:Dynamic):Void
		{
			if (setAsFinal)
				interp.finalVariables[key] = obj;
			else 
				switch Type.typeof(obj) {
					case TFunction | TClass(_) | TEnum(_): 
						interp.finalVariables[key] = obj;
					case _:
						interp.variables[key] = obj;
				}
		}

		setVar(key, obj);
		return this;
	}

	public function setClass(cl:Class<Dynamic>):SScript
	{
		if (_destroyed)
			return null;
		
		if (cl == null)
		{
			if (traces)
			{
				trace('Class cannot be null');
			}

			return null;
		}

		var clName:String = Type.getClassName(cl);
		if (clName != null)
		{
			var splitCl:Array<String> = clName.split('.');
			if (splitCl.length > 1)
			{
				clName = splitCl[splitCl.length - 1];
			}

			set(clName, cl);
		}
		return this;
	}

	public function setClassString(cl:String):SScript
	{
		if (_destroyed)
			return null;

		if (cl == null || cl.length < 1)
		{
			if (traces)
				trace('Class cannot be null');

			return null;
		}

		var cls:Class<Dynamic> = Type.resolveClass(cl);
		if (cls != null)
		{
			if (cl.split('.').length > 1)
			{
				cl = cl.split('.')[cl.split('.').length - 1];
			}

			set(cl, cls);
		}
		return this;
	}

	public function setSpecialObject(obj:Dynamic, ?includeFunctions:Bool = true, ?exclusions:Array<String>):SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return this;
		if (obj == null)
			return this;
		if (exclusions == null)
			exclusions = new Array();

		var types:Array<Dynamic> = [Int, String, Float, Bool, Array];
		for (i in types)
			if (Std.isOfType(obj, i))
				throw 'Special object cannot be ${i}';

		if (interp.specialObject == null)
			interp.specialObject = {obj: null, includeFunctions: null, exclusions: null};

		interp.specialObject.obj = obj;
		interp.specialObject.exclusions = exclusions.copy();
		interp.specialObject.includeFunctions = includeFunctions;
		return this;
	}

	public function locals():Map<String, Dynamic>
	{
		if (_destroyed)
			return null;

		if (!active)
			return [];

		var newMap:Map<String, Dynamic> = new Map();
		for (i in interp.locals.keys())
		{
			var v = interp.locals[i];
			if (v != null)
				newMap[i] = v.r;
		}
		return newMap;
	}

	public function unset(key:String):SScript
	{
		if (_destroyed)
			return null;
		if (BlankReg.match(key) || !classReg.match(key))
			return this;
		if (!active)
				return null;

		for (i in [interp.finalVariables, interp.variables])
		{
			if (i.exists(key))
			{
				i.remove(key);
			}
		}

		return this;
	}

	public function get(key:String):Dynamic
	{
		if (_destroyed)
			return null;
		if (BlankReg.match(key) || !classReg.match(key))
			return null;

		if (!active)
		{
			if (traces)
				trace("This tea is not active!");

			return null;
		}

		var l = locals();
		if (l.exists(key))
			return l[key];

		var r = interp.finalVariables.get(key);
		if (r == null)
			r = interp.variables.get(key);

		return r;
	}

	public function call(func:String, ?args:Array<Dynamic>):Tea
	{
		if (_destroyed)
			return {
				exceptions: [new TeaException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "Tea instance") + " is destroyed."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null,
				lastReportedTime: -1
			};

		if (!active)
			return {
				exceptions: [new TeaException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "Tea instance") + " is not active."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null,
				lastReportedTime: -1
			};

		var time:Float = Timer.stamp();

		var scriptFile:String = if (scriptFile != null && scriptFile.length > 0) scriptFile else "";
		var caller:Tea = {
			exceptions: [],
			calledFunction: func,
			succeeded: false,
			returnValue: null,
			lastReportedTime: -1
		}
		#if sys
		if (scriptFile != null && scriptFile.length > 0)
			Reflect.setField(caller, "fileName", scriptFile);
		#end
		if (args == null)
			args = new Array();

		var pushedExceptions:Array<String> = new Array();
		function pushException(e:String)
		{
			if (!pushedExceptions.contains(e))
				caller.exceptions.push(new TeaException(new Exception(e)));
			
			pushedExceptions.push(e);
		}
		if (func == null || BlankReg.match(func) || !classReg.match(func))
		{
			if (traces)
				trace('Function name cannot be invalid for $scriptFile!');

			pushException('Function name cannot be invalid for $scriptFile!');
			return caller;
		}
		
		var fun = get(func);
		if (exists(func) && Type.typeof(fun) != TFunction)
		{
			if (traces)
				trace('$func is not a function');

			pushException('$func is not a function');
		}
		else if (!exists(func))
		{
			if (traces)
				trace('Function $func does not exist in $scriptFile.');

			if (scriptFile != null && scriptFile.length > 0)
				pushException('Function $func does not exist in $scriptFile.');
			else 
				pushException('Function $func does not exist in Tea instance.');
		}
		else 
		{
			var oldCaller = caller;
			try
			{
				var functionField:Dynamic = Reflect.callMethod(this, fun, args);
				caller = {
					exceptions: caller.exceptions,
					calledFunction: func,
					succeeded: true,
					returnValue: functionField,
					lastReportedTime: -1,
				};
				#if sys
				if (scriptFile != null && scriptFile.length > 0)
					Reflect.setField(caller, "fileName", scriptFile);
				#end
				Reflect.setField(caller, "lastReportedTime", Timer.stamp() - time);
			}
			catch (e)
			{
				caller = oldCaller;
				caller.exceptions.insert(0, new TeaException(e));
			}
		}

		return caller;
	}

	public function clear():SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return this;

		for (i in interp.variables.keys())
				interp.variables.remove(i);

		for (i in interp.finalVariables.keys())
			interp.finalVariables.remove(i);

		return this;
	}

	public function exists(key:String):Bool
	{
		if (_destroyed)
			return false;
		if (!active)
			return false;
		if (BlankReg.match(key) || !classReg.match(key))
			return false;

		var l = locals();
		if (l.exists(key))
			return l.exists(key);

		for (i in [interp.variables, interp.finalVariables])
		{
			if (i.exists(key))
				return true;
		}
		return false;
	}

	public function preset():Void
	{
		if (_destroyed)
			return;
		if (!active)
			return;

		presetter.preset();
	}

	function resetInterp():Void
	{
		if (_destroyed)
			return;

		interp.locals = #if haxe3 new Map() #else new Hash() #end;
		while (interp.declared.length > 0)
			interp.declared.pop();
		while (interp.pushedVars.length > 0)
			interp.pushedVars.pop();
	}

	function destroyInterp():Void 
	{
		if (_destroyed)
			return;

		interp.locals = null;
		interp.variables = null;
		interp.finalVariables = null;
		interp.declared = null;
	}

	function doFile(scriptPath:String):Void
	{
		if (_destroyed)
			return;

		if (scriptPath == null || scriptPath.length < 1 || BlankReg.match(scriptPath))
		{
			ID = IDCount + 1;
			IDCount++;
			global[Std.string(ID)] = this;
			return;
		}

		if (scriptPath != null && scriptPath.length > 0)
		{
			#if sys
				if (FileSystem.exists(scriptPath))
				{
					scriptFile = scriptPath;
					script = File.getContent(scriptPath);
				}
				else
				{
					scriptFile = "";
					script = scriptPath;
				}
			#else
				scriptFile = "";
				script = scriptPath;
			#end

			if (scriptFile != null && scriptFile.length > 0)
				global[scriptFile] = this;
			else if (script != null && script.length > 0)
				global[script] = this;
		}
	}

	public function doString(string:String, ?origin:String):SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return null;
		if (string == null || string.length < 1 || BlankReg.match(string))
			return this;

		parsingException = null;

		var time = Timer.stamp();
		try 
		{
			#if sys
			if (FileSystem.exists(string.trim()))
				string = string.trim();
			
			if (FileSystem.exists(string))
			{
				scriptFile = string;
				origin = string;
				string = File.getContent(string);
			}
			#end

			var og:String = origin;
			if (og != null && og.length > 0)
				customOrigin = og;
			if (og == null || og.length < 1)
				og = customOrigin;
			if (og == null || og.length < 1)
				og = "SScript";

			resetInterp();
		
			script = string;
			
			if (scriptFile != null && scriptFile.length > 0)
			{
				if (ID != null)
					global.remove(Std.string(ID));
				global[scriptFile] = this;
			}
			else if (script != null && script.length > 0)
			{
				if (ID != null)
					global.remove(Std.string(ID));
				global[script] = this;
			}

			function tryHaxe()
			{
				try 
				{
					var expr:Expr = parser.parseString(script, og);
					var r = interp.execute(expr);
					returnValue = r;
				}
				catch (e) 
				{
					parsingException = e;				
					returnValue = null;
				}

				if (defaultFunc != null)
					call(defaultFunc);
			}

			tryHaxe();	
			
			lastReportedTime = Timer.stamp() - time;
 
			if (debugTraces)
			{
				if (lastReportedTime == 0)
					trace('Tea instance brewed instantly (0s)');
				else 
					trace('Tea instance brewed in ${lastReportedTime}s');
			}
		}
		catch (e) lastReportedTime = -1;

		return this;
	}

	inline function toString():String
	{
		if (_destroyed)
			return "null";

		if (scriptFile != null && scriptFile.length > 0)
			return scriptFile;

		return "Tea";
	}

	public static function listScripts(path:String, ?extensions:Array<String>):Array<SScript>
	{
		if (!path.endsWith('/'))
			path += '/';

		if (extensions == null || extensions.length < 1)
			extensions = ['hx'];

		var list:Array<SScript> = [];
		#if sys
		if (FileSystem.exists(path) && FileSystem.isDirectory(path))
		{
			var files:Array<String> = FileSystem.readDirectory(path);
			for (i in files)
			{
				var hasExtension:Bool = false;
				for (l in extensions)
				{
					if (i.endsWith(l))
					{
						hasExtension = true;
						break;
					}
				}
				if (hasExtension && FileSystem.exists(path + i))
					list.push(new SScript(path + i));
			}
		}
		#end
		
		return list;
	}

	public function destroy():Void
	{
		if (_destroyed)
			return;

		if (global.exists(scriptFile) && scriptFile != null && scriptFile.length > 0)
			global.remove(scriptFile);
		else if (global.exists(script) && script != null && script.length > 0)
			global.remove(script);
		if (global.exists(Std.string(ID)))
			global.remove(script);
		
		if (classPath != null && classPath.length > 0)
		{
			Interp.classes.remove(classPath);
			Interp.STATICPACKAGES[classPath] = null;
			Interp.STATICPACKAGES.remove(classPath);
		}

		for (i in interp.pushedClasses)
		{
			Interp.classes.remove(i);
			Interp.STATICPACKAGES[i] = null;
			Interp.STATICPACKAGES.remove(i);
		} 

		for (i in interp.pushedAbs)
		{
			Interp.eabstracts.remove(i);
			Interp.EABSTRACTS[i].tea = null;
			Interp.EABSTRACTS[i].fileName = null;
			Interp.EABSTRACTS.remove(i);
		} 
		
		for (i in interp.pushedVars) 
		{
			if (globalVariables.exists(i))
				globalVariables.remove(i);
		}

		presetter.destroy();

		clear();
		resetInterp();
		destroyInterp();

		parsingException = null;
		customOrigin = null;
		parser = null;
		interp = null;
		script = null;
		scriptFile = null;
		active = false;
		improvedField = null;
		notAllowedClasses = null;
		lastReportedTime = -1;
		ID = null;
		returnValue = null;
		_destroyed = true;
	}

	function get_variables():Map<String, Dynamic>
	{
		if (_destroyed)
			return null;

		return interp.variables;
	}

	function get_classPath():String 
	{
		if (_destroyed)
			return null;

		return classPath;
	}

	function setClassPath(p):String 
	{
		if (_destroyed)
			return null;

		return classPath = p;
	}

	function setPackagePath(p):String
	{
		if (_destroyed)
			return null;

		return packagePath = p;
	}

	function get_packagePath():String
	{
		if (_destroyed)
			return null;

		return packagePath;
	}

	function set_customOrigin(value:String):String
	{
		if (_destroyed)
			return null;
		
		@:privateAccess parser.origin = value;
		return customOrigin = value;
	}

	function set_improvedField(value:Null<Bool>):Null<Bool> 
	{
		if (_destroyed)
			return null;

		if (interp != null)
			interp.improvedField = value == null ? false : value;
		return improvedField = value;
	}

	static function get_BlankReg():EReg 
	{
		return ~/^[\n\r\t]$/;
	}

	static function get_classReg():EReg 
	{
		return  ~/^[a-zA-Z_][a-zA-Z0-9_]*$/;
	}

	static function set_defaultTypeCheck(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			if (i != null && !i._destroyed)
				i.typeCheck = value == null ? false : value;
		}

		return defaultTypeCheck = value;
	}

	static function set_defaultDebug(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			if (i != null && !i._destroyed)
				i.debugTraces = value == null ? false : value;
		}
	
		return defaultDebug = value;
	}

	static function set_defaultFun(value:String):String 
	{
		for (i in global) 
		{
			if (i != null && !i._destroyed)
				i.defaultFunc = value;
		}

		return defaultFun = value;
	}

	static function set_defaultImprovedField(value:Null<Bool>):Null<Bool> 
	{
		for (i in global) 
		{
			if (i != null && !i._destroyed)
				i.improvedField = value;
		}

		return defaultImprovedField = value;
	}
}