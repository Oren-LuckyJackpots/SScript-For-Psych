package tea;

import ex.*;

import haxe.Exception;
import haxe.Timer;

import hscriptBase.*;
import hscriptBase.Expr;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import tea.backend.*;
import tea.backend.crypto.Base32;

using StringTools;

typedef TeaCall =
{
	#if sys
	public var ?fileName(default, null):String;
	#end
	
	public var succeeded(default, null):Bool;

	
	public var calledFunction(default, null):String;

	
	public var returnValue(default, null):Null<Dynamic>;

	
	public var exceptions(default, null):Array<SScriptException>;
}

/**
	The base class for dynamic Haxe scripts.
**/
@:structInit
@:access(hscriptBase.Interp)
@:access(hscriptBase.Parser)
@:keepSub
class SScript
{
	public static var IGNORE_RETURN(default, never):Dynamic = "#0IGNORE#0RETURN#0VALUE#0";

	public static var STOP_RETURN(default, never):Dynamic = "#1STOP#1RETURN#1VALUE#1";

	public static var VERSION(default, null):SScriptVer = new SScriptVer(7, 7, 0);
	
	public static var defaultTypeCheck(default, set):Null<Bool> = true;

	public static var defaultDebug(default, set):Null<Bool> = #if debug true #else null #end;

	public static var globalVariables:SScriptGlobalMap = new SScriptGlobalMap();

	public static var global(default, null):Map<String, SScript> = [];
	
	static var IDCount(default, null):Int = 0;

	static var BlankReg(get, never):EReg;

	public var customOrigin(default, set):String;

	public var returnValue(default, null):Null<Dynamic>;

	public var ID(default, null):Null<Int> = null;

	public var typeCheck:Bool = false;

	public var lastReportedTime(default, null):Float = -1;

	public var lastReportedCallTime(default, null):Float = -1;

	public var notAllowedClasses(default, null):Array<Class<Dynamic>> = [];

	public var variables(get, never):Map<String, Dynamic>;

	public var interp(default, null):Interp;

	public var parser(default, null):Parser;

	public var script(default, null):String = "";

	public var active:Bool = true;

	public var scriptFile(default, null):String = "";

	public var traces:Bool = false;

	public var debugTraces:Bool = false;

	public var parsingException(default, null):SScriptException;

	public var packagePath(get, null):String = "";

	@:deprecated("parsingExceptions are deprecated, use parsingException instead")
	var parsingExceptions(get, never):Array<Exception>;

	@:noPrivateAccess var _destroyed(default, null):Bool;

	public function new(?scriptPath:String = "", ?preset:Bool = true, ?startExecute:Bool = true)
	{
		var time = Timer.stamp();

		if (defaultTypeCheck != null)
			typeCheck = defaultTypeCheck;
		if (defaultDebug != null)
			debugTraces = defaultDebug;

		interp = new Interp();
		interp.setScr(this);

		parser = new Parser();

		if (preset)
			this.preset();

		for (i => k in globalVariables)
		{
			if (i != null)
				set(i, k);
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
					trace('SScript instance created instantly (0s)');
				else 
					trace('SScript instance created in ${lastReportedTime}s');
			}
		}
		catch (e)
		{
			lastReportedTime = -1;
		}
	}

	public function execute():Void
	{
		if (_destroyed)
			return;

		if (interp == null || !active)
			return;

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
		}
	}

	public function set(key:String, obj:Dynamic):SScript
	{
		if (_destroyed)
			return null;

		if (obj != null && (obj is Class) && notAllowedClasses.contains(obj))
			throw 'Tried to set ${Type.getClassName(obj)} which is not allowed.';

		function setVar(key:String, obj:Dynamic):Void
		{
			if (key == null)
				return;

			if (Tools.keys.contains(key))
				throw '$key is a keyword, set something else';
			if (!active)
				return;

			if (interp == null || !active)
			{
				if (traces)
				{
					if (interp == null)
						trace("This script is unusable!");
					else
						trace("This script is not active!");
				}
			}
			else
				interp.variables[key] = obj;
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
			interp.specialObject = {obj: null , includeFunctions: null , exclusions: null };

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

		if (interp == null || !active || key == null || !interp.variables.exists(key))
				return null;

		interp.variables.remove(key);
		return this;
	}

	public function get(key:String):Dynamic
	{
		if (_destroyed)
			return null;

		if (interp == null || !active)
		{
			if (traces)
			{
				if (interp == null)
					trace("This script is unusable!");
				else
					trace("This script is not active!");
			}

			return null;
		}

		var l = locals();
		if (l.exists(key))
			return l[key];

		return if (exists(key)) interp.variables[key] else null;
	}

	public function call(func:String, ?args:Array<Dynamic>):TeaCall
	{
		if (_destroyed)
			return {
				exceptions: [new SScriptException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "SScript instance") + " is destroyed."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null
			};

		if (!active)
			return {
				exceptions: [new SScriptException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "SScript instance") + " is not active."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null
			};

		var time:Float = Timer.stamp();

		var scriptFile:String = if (scriptFile != null && scriptFile.length > 0) scriptFile else "";
		var caller:TeaCall = {
			exceptions: [],
			calledFunction: func,
			succeeded: false,
			returnValue: null
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
				caller.exceptions.push(new SScriptException(new Exception(e)));
			
			pushedExceptions.push(e);
		}
		if (func == null)
		{
			if (traces)
				trace('Function name cannot be null for $scriptFile!');

			pushException('Function name cannot be null for $scriptFile!');
			return caller;
		}
		
		var fun = get(func);
		if (exists(func) && Type.typeof(fun) != TFunction)
		{
			if (traces)
				trace('$func is not a function');

			pushException('$func is not a function');
		}
		else if (interp == null || !exists(func))
		{
			if (interp == null)
			{
				if (traces)
					trace('Interpreter is null!');

				pushException('Interpreter is null!');
			}
			else
			{
				if (traces)
					trace('Function $func does not exist in $scriptFile.');

				if (scriptFile != null && scriptFile.length > 1)
					pushException('Function $func does not exist in $scriptFile.');
				else 
					pushException('Function $func does not exist in SScript instance.');
			}
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
					returnValue: functionField
				};
				#if sys
				if (scriptFile != null && scriptFile.length > 0)
					Reflect.setField(caller, "fileName", scriptFile);
				#end
			}
			catch (e)
			{
				caller = oldCaller;
				caller.exceptions.insert(0, new SScriptException(e));
			}
		}
		lastReportedCallTime = Timer.stamp() - time;

		return caller;
	}

	public function clear():SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return this;

		if (interp == null)
			return this;

		var importantThings:Array<String> = ['true', 'false', 'null', 'trace'];

		for (i in interp.variables.keys())
			if (!importantThings.contains(i))
				interp.variables.remove(i);

		return this;
	}

	public function exists(key:String):Bool
	{
		if (_destroyed)
			return false;
		if (!active)
			return false;

		if (interp == null)
			return false;
		var l = locals();
		if (l.exists(key))
			return l.exists(key);

		return interp.variables.exists(key);
	}

	public function preset():Void
	{
		if (_destroyed)
			return;
		if (!active)
			return;

		setClass(Date);
		setClass(DateTools);
		setClass(Math);
		setClass(Reflect);
		setClass(Std);
		setClass(SScript);
		setClass(StringTools);
		setClass(Type);

		#if sys
		setClass(File);
		setClass(FileSystem);
		setClass(Sys);
		#end
	}

	function resetInterp():Void
	{
		if (_destroyed)
			return;
		if (interp == null)
			return;

		interp.locals = #if haxe3 new Map() #else new Hash() #end;
		while (interp.declared.length > 0)
			interp.declared.pop();
	}

	function doFile(scriptPath:String):Void
	{
		parsingException = null;

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

			if (!active || interp == null)
				return null;

			resetInterp();

			try
			{	
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

				var expr:Expr = parser.parseString(script, og);
				var r = interp.execute(expr);
				returnValue = r;
			}
			catch (e)
			{
				script = "";
				parsingException = e;
				returnValue = null;
			}
			
			lastReportedTime = Timer.stamp() - time;
 
			if (debugTraces)
			{
				if (lastReportedTime == 0)
					trace('SScript instance created instantly (0s)');
				else 
					trace('SScript instance created in ${lastReportedTime}s');
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

		return "[SScript SScript]";
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

		if (global.exists(script) && script != null && script.length > 0)
			global.remove(script);
		if (global.exists(scriptFile) && scriptFile != null && scriptFile.length > 0)
			global.remove(scriptFile);

		clear();
		resetInterp();

		customOrigin = null;
		parser = null;
		interp = null;
		script = null;
		scriptFile = null;
		active = false;
		notAllowedClasses = null;
		lastReportedCallTime = -1;
		lastReportedTime = -1;
		ID = null;
		parsingException = null;
		returnValue = null;
		_destroyed = true;
	}

	function get_variables():Map<String, Dynamic>
	{
		if (_destroyed)
			return null;

		return interp.variables;
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

	static function get_BlankReg():EReg 
	{
		return ~/^[\n\r\t]$/;
	}

	function set_customOrigin(value:String):String
	{
		if (_destroyed)
			return null;
		
		@:privateAccess parser.origin = value;
		return customOrigin = value;
	}

	static function set_defaultTypeCheck(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			i.typeCheck = value == null ? false : value;
			//i.execute();
		}

		return defaultTypeCheck = value;
	}

	static function set_defaultDebug(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			i.debugTraces = value == null ? false : value;
			//i.execute();
		}
	
		return defaultDebug = value;
	}

	function get_parsingExceptions():Array<Exception> 
	{
		if (_destroyed)
			return null;

		if (parsingException == null)
			return [];

		return @:privateAccess [parsingException.toException()];
	}
}