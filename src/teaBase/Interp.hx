/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package teaBase;

import haxe.ds.*;
import haxe.PosInfos;
import teaBase.Expr;
import haxe.Constraints;
import tea.SScript;

using StringTools;

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

private enum SScriptNull {
	Not_NULL;
}

@:keepSub
@:access(teaBase.TeaClass)
@:access(teaBase.Parser)
@:access(tea.SScript)
class Interp {

	static var eabstracts:Array<String> = [];
	static var EABSTRACTS:Map<String, { ?fileName : String , tea : TeaEAbstract }> = [];
	static var classes:Array<String> = [];
	static var STATICPACKAGES:Map<String, { ?fileName : String , tea : TeaClass }> = [];
	var pushedVars:Array<String> = [];
	var pushedClasses:Array<String> = [];
	var pushedAbs:Array<String> = [];

	#if haxe3
	public var variables : Map<String,Dynamic>;
	var finalVariables : Map<String,Dynamic>;
	var locals : Map<String,{ r : Dynamic , ?isFinal : Bool , ?t:CType , ?dynamicFunc : Bool }>;
	var binops : Map<String, Expr -> Expr -> Dynamic >;
	#else
	public var variables : Hash<Dynamic>;
	var locals : Hash<{ r : Dynamic }>;
	var binops : Hash< Expr -> Expr -> Dynamic >;
	#end

	var depth : Int;
	var inTry : Bool;
	var declared : Array<{ n : String, old : { r : Dynamic , ?isFinal : Bool , ?t:CType, ?dynamicFunc : Bool } }>;
	var returnValue : Dynamic;

	var typecheck : Bool = true;

	var privateAccess : Bool = false;

	var script : SScript;

	var curExpr : Expr;

	var specialObject : {obj:Dynamic , ?includeFunctions:Bool , ?exclusions:Array<String>} = {obj : null , includeFunctions: null , exclusions: null };

	var inPublic : Bool = false;
	var inPrivate : Bool = false;
	var inClass : Bool = false;

	var inStatic : Bool = false;

	var hasPrivateAccess : Bool = false;
	var noPrivateAccess : Bool = false;

	var strictVar : Bool = false;
	var inBool : Bool = false;

	var inCall : Bool = false;
	var currentArg : String;

	var improvedField : Bool = true;

	var curClass : String;

	public inline function setScr(s)
	{
		return script = s;
	}

	var resumeError : Bool = false;
	var canUseAbs : Bool = false;

	public function new() {
		#if haxe3
		locals = new Map();
		#else
		locals = new Hash();
		#end
		declared = new Array();
		resetVariables();
		initOps();
	}

	private function resetVariables(){
		#if haxe3
		variables = new Map<String,Dynamic>();
		finalVariables = new Map();
		#else
		variables = new Hash();
		#end

		finalVariables.set("null",null);
		finalVariables.set("true",true);
		finalVariables.set("false",false);
		finalVariables.set("trace", Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if( el.length > 0 ) inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
		finalVariables.set("Bool", Bool);
		finalVariables.set("Int", Int);
		finalVariables.set("Float", Float);
		finalVariables.set("String", String);
		finalVariables.set("Dynamic", Dynamic);
		finalVariables.set("Array", Array);
	}

	public function posInfos(): PosInfos {
		if(curExpr != null)
			return cast { fileName : curExpr.origin, lineNumber : curExpr.line };
		return cast { fileName : "SScript", lineNumber : 0 };
	}

	var inFunc : Bool = false;
	var abortFunc : Bool = false;
	var returnedNothing : Bool = true;

	var newFunc = { func : null , arguments : null };

	function initOps() {
		var me = this;
		#if haxe3
		binops = new Map();
		#else
		binops = new Hash();
		#end
		binops.set("+",function(e1,e2) return me.expr(e1) + me.expr(e2));
		binops.set("-",function(e1,e2) return me.expr(e1) - me.expr(e2));
		binops.set("*",function(e1,e2) return me.expr(e1) * me.expr(e2));
		binops.set("/",function(e1,e2) return me.expr(e1) / me.expr(e2));
		binops.set("%",function(e1,e2) return me.expr(e1) % me.expr(e2));
		binops.set("&",function(e1,e2) return me.expr(e1) & me.expr(e2));
		binops.set("|",function(e1,e2) return me.expr(e1) | me.expr(e2));
		binops.set("^",function(e1,e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<",function(e1,e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>",function(e1,e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>",function(e1,e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==",function(e1,e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=",function(e1,e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=",function(e1,e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=",function(e1,e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">",function(e1,e2) return me.expr(e1) > me.expr(e2));
		binops.set("<",function(e1,e2) return me.expr(e1) < me.expr(e2));
		binops.set("||",function(e1,e2) return me.expr(e1) == true || me.expr(e2) == true);
		binops.set("&&",function(e1,e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("=",assign);
		binops.set("is",checkIs);
		binops.set("...",function(e1,e2) return new InterpIterator(me, e1, e2));
		assignOp("+=",function(v1:Dynamic,v2:Dynamic) return v1 + v2);
		assignOp("-=",function(v1:Float,v2:Float) return v1 - v2);
		assignOp("*=",function(v1:Float,v2:Float) return v1 * v2);
		assignOp("/=",function(v1:Float,v2:Float) return v1 / v2);
		assignOp("%=",function(v1:Float,v2:Float) return v1 % v2);
		assignOp("&=",function(v1,v2) return v1 & v2);
		assignOp("|=",function(v1,v2) return v1 | v2);
		assignOp("^=",function(v1,v2) return v1 ^ v2);
		assignOp("<<=",function(v1,v2) return v1 << v2);
		assignOp(">>=",function(v1,v2) return v1 >> v2);
		assignOp(">>>=",function(v1,v2) return v1 >>> v2);
	}

	function checkIs(e1,e2) : Bool
	{
		var me = this;

		if( e1 == null )
			return false;
		if( e2 == null )
			return false;
		var expr1:Dynamic = me.expr(e1);
		var expr2:Dynamic = me.expr(e2);
		if( expr1 == null )
			return false;
		if( expr2 == null )
			return false;

		switch Tools.expr(e2)
		{
			case EIdent("Class"):
				return Std.isOfType(expr1, Class);
			case EIdent("Map"):
				return Std.isOfType(expr1, IMap);
			case _:
		}

		return Std.isOfType(expr1, expr2);
	}

	function coalesce(e1,e2) : Dynamic
	{
		var me = this;
		var e1=me.expr(e1);
		var e2=me.expr(e2);
		return e1 == null ? e2:e1;
	}

	function coalesce2(e1,e2) : Dynamic{
		var me = this;
		var expr1=e1;
		var expr2=e2;
		var e1=me.expr(e1);
		return if(e1==null) assign(expr1,expr2) else e1;
	}

	function setVar( name : String, v : Dynamic ) {
		var ftype:String = Tools.getType(variables.get(name));
		var stype:String = Tools.getType(v);
		var cl=variables.get(ftype);
		var clN=Tools.getType(v,true);

		if(typecheck)
		if(!Tools.compatibleWithEachOther(ftype, stype)&&ftype!=stype&&ftype!='Anon'&&!Tools.compatibleWithEachOtherObjects(cl,clN))error(EUnmatchingType(ftype, stype, name));
		variables.set(name, v);
	}

	function assign( e1 : Expr, e2 : Expr ) : Dynamic {
		var v = expr(e2);
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			if( locals.get(id)!=null&&locals.get(id).isFinal )
				return error(EInvalidFinal(id));
			var l = locals.get(id);
			if( l == null )
			{
				if( finalVariables.exists(id) )
					return error(EInvalidFinal(id));
		
				if(!variables.exists(id))
					error(EUnknownVariable(id));
				setVar(id,v);
			}
			else {
				var t=l.t;
				if(t!=null)
				{
					var ftype:String = Tools.ctToType(l.t);
					var stype:String = Tools.getType(v);
					var cl=variables.get(ftype);
					
					var clN=Tools.getType(v,true);
					if(typecheck)
					if(!Tools.compatibleWithEachOther(ftype, stype)&&ftype!=stype&&ftype!='Anon'&&!Tools.compatibleWithEachOtherObjects(cl,clN))error(EUnmatchingType(ftype, stype, id));
				}
				if(Type.typeof(l.r)==TFunction&&l.dynamicFunc!=null&&!l.dynamicFunc)
					error(EFunctionAssign(id));
				l.r = v;
			}
		case EField(e,f,fields):
			if( improvedField && fields != null && fields.length > 1 )
			{
				var r = findField(fields,'set',f,v);
				if( r != null )
					return r;
			}
			v = set(expr(e),f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if(isMap(arr)) {
				setMapValue(arr, index, v);
			}
			else {
				arr[index] = v;
			}

		default:
			error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp( op, fop : Dynamic -> Dynamic -> Dynamic ) {
		var me = this;
		binops.set(op,function(e1,e2) return me.evalAssignOp(op,fop,e1,e2));
	}

	function evalAssignOp(op,fop,e1,e2) : Dynamic {
		var v;
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			var l = locals.get(id);
			v = fop(expr(e1),expr(e2));
			if( l == null )
				setVar(id,v)
			else
				l.r = v;
		case EField(e,f,fields):
			var r = null;	
			if( improvedField && fields != null && fields.length > 1 )
				r = findField(fields,"op");
			var obj = r != null ? r : expr(e);
			v = fop(get(obj,f),expr(e2));
			v = set(obj,f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if(isMap(arr)) {
				v = fop(getMapValue(arr, index), expr(e2));
				setMapValue(arr, index, v);
			}
			else {
				v = fop(arr[index],expr(e2));
				arr[index] = v;
			}
		default:
			return error(EInvalidOp(op));
		}
		return v;
	}

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		curExpr = e;
		var oldExpr = e;
		var e = e.e;
		switch(e) {
		case EIdent(id):
			var l = locals.get(id);
			var v : Null<Dynamic> = (l == null) ? resolve(id) : l.r;
			if( v != null && !Std.isOfType(v,Float) )
				error(ECustom(Tools.checkType(v,Int)));
			if( prefix ) {
				v += delta;
				if( l == null ) setVar(id,v) else l.r = v;
			} else
				if( l == null ) setVar(id,v + delta) else l.r = v + delta;
			return v;
		case EField(e,f,fields):
			var r = null;	
			if( improvedField && fields != null && fields.length > 1 )
				r = findField(fields,"op");
			var obj = r != null ? r : expr(e);
			var v : Dynamic = get(obj,f);
			if( prefix ) {
				v += delta;
				set(obj,f,v);
			} else
				set(obj,f,v + delta);
			return v;
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if(isMap(arr)) {
				var v = getMapValue(arr, index);
				if(prefix) {
					v += delta;
					setMapValue(arr, index, v);
				}
				else {
					setMapValue(arr, index, v + delta);
				}
				return v;
			}
			else {
				var v = arr[index];
				if( prefix ) {
					v += delta;
					arr[index] = v;
				} else
					arr[index] = v + delta;
				return v;
			}
		case EConst(c): 
			switch c {
				case CFloat(_) | CInt(_):
					return error(EInvalidAssign);
				case _:
					var e:Null<Dynamic> = expr(oldExpr);
					return error(ECustom(Tools.checkType(e, Int)));
			}
		default:
			return error(EInvalidOp((delta > 0)?"++":"--"));
		}
	}

	public function execute( expr : Expr ) : Dynamic {
		depth = 0;
		#if haxe3
		locals = new Map();
		#else
		locals = new Hash();
		#end
		declared = new Array();
		switch Tools.expr(expr){
			case EBlock(e):
				var imports:Int = 0;
				var pack:Int = 0;
				for(i in e){
					switch Tools.expr(i)
					{
						case EPackage(_):
							if(e.indexOf(i)>0)
								error(EUnexpected("package"));
							else if(pack > 1)
								error(ECustom('Multiple packages has been declared'));
							pack++;
						case EImport(_,_,_) | EImportStar(_) | EUsing(_):
							if(e.indexOf(i)>imports + pack)
								error(EUnexpected("import"));
							imports++;
						case _:
					}
				}
				if(pack > 1)
					error(ECustom('Multiple packages has been declared'));
			case _:
		}
		var r = this.expr(expr);
		return r;
	}

	function exprReturn(e) : Dynamic {
		try {
			return expr(e);
		} catch( e : Stop ) {
			switch( e ) {
			case SBreak: throw "Invalid break";
			case SContinue: throw "Invalid continue";
			case SReturn:
				returnedNothing = false;
				var v = returnValue;
				returnValue = null;
				return v;
			}
		}
		return null;
	}

	var shouldAbort = false;
	function duplicate<T>( h : #if haxe3 Map < String, T > #else Hash<T> #end ) {
		#if haxe3
		var h2 = new Map();
		#else
		var h2 = new Hash();
		#end
		for( k in h.keys() )
			h2.set(k,h.get(k));
		return h2;
	}

	function restore( old : Int ) {
		while( declared.length > old ) {
			var d = declared.pop();
			locals.set(d.n,d.old);
		}
	}

	inline function error(e : ErrorDef , rethrow=false ) : Dynamic {
		if(resumeError)return null;
		if( curExpr == null )
			curExpr = { origin: {
				if(script.customOrigin != null && script.customOrigin.length > 0)
					script.customOrigin;
				else if(script.scriptFile != null && script.scriptFile.length > 0)
					script.scriptFile;
				else 
					"SScript";
			} , pmin : 0 , pmax : 0 , line : 0 , e : null };
		var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line);
		if( rethrow ) this.rethrow(e) else throw e;
		return null;
	}

	inline function rethrow( e : Dynamic ) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	function resolve( id : String ) : Dynamic { 
		var l = locals.get(id);
		if( l != null )
			return l.r;
		if( STATICPACKAGES.exists(id) )
			return STATICPACKAGES[id].tea;
		else if( EABSTRACTS.exists(id) )
			return canUseAbs ? EABSTRACTS[id].tea : error(ECannotUseAbs);
		if( specialObject != null && specialObject.obj != null )
		{
			var field = Reflect.getProperty(specialObject.obj,id);
			if( field != null && (specialObject.includeFunctions || Type.typeof(field) != TFunction) && (specialObject.exclusions == null || !specialObject.exclusions.contains(id)) )
				return field;
		}
		if( finalVariables.exists("this") ) {
			var v = finalVariables["this"];
			if( Reflect.hasField(v,id) )
				return Reflect.getProperty(v,id);
		}
		var v = finalVariables.get(id);
		if( finalVariables.exists(id) )
			return v;
		var v = variables.get(id);
		if( v==null && !variables.exists(id) )
			error(EUnknownVariable(id));
		return v;
	}

	public function expr( e : Expr ) : Dynamic {
		curExpr = e;
		var og = e;
		var e = e.e;
		switch( e ) {
		case EEAbstract(ident,parent,exprs,fromParent):
			if( eabstracts.contains(ident) || classes.contains(ident) )
			{
				var tea = null;
				if( EABSTRACTS[ident] != null )
					tea = EABSTRACTS[ident].fileName;
				else if( STATICPACKAGES[ident] != null )
					tea = STATICPACKAGES[ident].fileName;
				error(EAlreadyModule(ident,tea));
			}
			else if( ident == ident.toLowerCase() )
				error(ETypeName);

			var abstractValueInt = -1;
			eabstracts.push(ident);
			pushedAbs.push(ident);
			var eabstract = new TeaEAbstract(ident);
			for( i in exprs ) {
				var isPublic = true;
				var evar = null;
				switch i.e {
					case EVar(_,_,_,_): evar = i.e;
					case EPublic(e): switch e.e {
						case EVar(_,_,_,_): evar = e.e;
						case _:
					}
					case EPrivate(e): switch e.e {
						case EVar(_,_,_,_): 
							isPublic = false;
							evar = e.e;
						case _:
					} 
					case _:
				}

				if( evar != null ) {
					var name:String = null,value:Null<Dynamic> = null,type:String = null;
					var reallyNull = false;
					switch evar {
						case EVar(n,_,t,e):
							if( e == null ) reallyNull = true;
							name = n;
							value = e != null ? expr(e) : null;
							type = t != null ? Tools.ctToType(t) : null;
						case _:
					}
					var sugar = TeaEAbstract.createSugar(isPublic,name,value);
					if( eabstract.fields.exists(name) )
						error(ECustom("Duplicate abstract field declaration : " + ident + "." + name));
					if( parent == "Int" ) {
						if( value == null && reallyNull ) 
						{
							sugar.v = abstractValueInt + 1;
							abstractValueInt++;
						}
						else if( value != null && abstractValueInt != value && !reallyNull ) abstractValueInt = sugar.v;
						else if( !(value != null && abstractValueInt == value) ) abstractValueInt++;
					}
					else if( parent == "String" && value == null && reallyNull ) {
						sugar.v = name;
					}

					eabstract.fields[name] = sugar;
				}
			}
			var fileName = null;
			if( script.customOrigin != null && script.customOrigin.length > 0 )
				fileName = script.customOrigin;
			else if( script.scriptFile != null && script.scriptFile.length > 0 )
				fileName = script.scriptFile;
			EABSTRACTS[ident] = { fileName : fileName , tea : eabstract }
			return if( strictVar ) error(EUnexpected("enum")) else null;
		case EClass(cl,e):
			if( classes.contains(cl) || eabstracts.contains(cl) )
			{
				var tea = null;
				if( EABSTRACTS[cl] != null )
					tea = EABSTRACTS[cl].fileName;
				else if( STATICPACKAGES[cl] != null )
					tea = STATICPACKAGES[cl].fileName;
				error(EMultipleDecl(cl,tea));
			}
			else if( cl == cl.toLowerCase() )
				error(ETypeName);

			inClass = true;
			for( e in e ) {
				var expr = e.e;
				switch expr {
					case EPublic(e):
						switch e.e {
							case EStatic(_,_):
							case _: 
						}
					case EPrivate(e):
						switch e.e {
							case EStatic(_,_):
							case _: 
						}
					case EStatic(_,_):
					case _: 
				}
			}

			classes.push(cl);
			pushedClasses.push(cl);
			script.setClassPath(cl);
			curClass = cl;
			var v = null;
			if( !STATICPACKAGES.exists(cl) )
			{
				var fileName = null;
				if( script.customOrigin != null && script.customOrigin.length > 0 )
					fileName = script.customOrigin;
				else if( script.scriptFile != null && script.scriptFile.length > 0 )
					fileName = script.scriptFile;

				v = new TeaClass(cl);
				STATICPACKAGES.set(cl,{ fileName : fileName , tea : v });
			}
			for( e in e ) switch e.e {
				case _: expr(e);
			}
			inClass = false;
			return if( strictVar ) error(EUnexpected("class")) else null;
		case EPublic(e):
			if( inPublic && !inStatic )
				error(EUnexpected("public"));
			
			inPrivate = false;
			inPublic = true;
			expr(e);
			inPublic = false;
			return if( strictVar ) error(EUnexpected("public")); else null;
		case EPrivate(e):
			if( inPrivate && !inStatic )
				error(EUnexpected("private"));

			inPublic = false;
			inPrivate = true;
			expr(e);
			inPrivate = false;
			return if( strictVar ) error(EUnexpected("private")) else null;
		case EStatic(e,inPublic):
			inStatic = true;
			if( inPublic != null )
			{
				this.inPublic = inPublic;
				inPrivate = !inPublic;
			}
			expr(e);
			inStatic = false;
			return if( strictVar ) error(EUnexpected("static")) else null;
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			#if !haxe3
			case CInt32(v): return v;
			#end
			}
		case EInterpString(string, interpolatedString):
			var s = string.copy();
			for( i in interpolatedString ) {
				var str = s[i.index];
				if( str != null ) {
					script.parser.inInterp = true;
					var expr = Std.string(expr(script.parser.parseString(i.str)));
					script.parser.inInterp = false;
					str = str.replace(i.str, expr);
					s[i.index] = str;
				}
			}
			return s.join('');	
		case EEReg(chars, ops):
			#if !(cpp || neko) // not supported on other targets
			ops = ops.split('u').join('');
			#end

			#if (cs || js) // not supported on C# and JavaScript
			ops = ops.split('s').join('');
			#end

			return new EReg(chars,ops);
		case EIdent(id):
			strictVar = true;
			var e = resolve(id);
			strictVar = false;
			return e;
		case EVar(n,f,t,e):
			if(t!=null&&e!=null)
			{
				var e = expr(e);
				var ftype:String = Tools.ctToType(t);
				var stype:String = Tools.getType(e);
				var cl=variables.get(ftype);
				var clN=Tools.getType(e,true);

				if(typecheck)
				if(!Tools.compatibleWithEachOther(ftype, stype)&&ftype!=stype&&ftype!='Anon'&&!Tools.compatibleWithEachOtherObjects(cl,clN)){error(EUnmatchingType(ftype, stype, n));}
			}

			strictVar = true;
			var expr1 : Dynamic = e == null ? null : expr(e);
			strictVar = false;
			var name = null;
			var isMap = t != null && e != null && (switch t {
				case CTPath(path,_):
					if( path.length == 1 && isMap(path[0])) 
					{
						name = path[0];
						true;
					}
					else false;
				case _: false;
			}) && (switch Tools.expr(e) {
				case EArrayDecl(e): 
					if( e.length < 1 ) true;
					else false;
				case _: false;
			});

			if( isMap ) 
				switch name {
					case "IntMap": expr1 = new IntMap<Dynamic>();
					case "StringMap": expr1 = new StringMap<Dynamic>();
					case "Map" | "ObjectMap": expr1 = new ObjectMap<Dynamic, Dynamic>();
					case _: 
				};

			var variables = f ? finalVariables : variables;
			if( !inStatic )
			{
				if( !inPublic && !inPublic )
				{
					declared.push({ n : n, old : locals.get(n) });
					locals.set(n,{ r : expr1 , isFinal : f, t: t});
				}
				else 
					variables.set(n,expr1);
			}
			else
			{
				variables.set(n,expr1);
				if( script.classPath != null && script.classPath.length > 0 && STATICPACKAGES.exists(script.classPath) )
					STATICPACKAGES.get(script.classPath).tea.fields.set(n,TeaClass.createSugar(inPublic && !noPrivateAccess, expr1, f, noPrivateAccess, false));
				else if( inPublic ) 
				{
					if( !pushedVars.contains(n) ) {
						pushedVars.push(n);
						SScript.globalVariables.set(n,expr1);
					}
				}
			}
			return if( strictVar ) error(EUnexpected(f ? "final" : "var")) else null;
		case EParent(e):
			return expr(e);
		case EBlock(exprs):
			var old = declared.length;
			var v = null;
			for( e in exprs ) {
				if( !shouldAbort )
				{
					v = expr(e);
				}
				else 
				{
					shouldAbort = false;
					restore(old);
					break;
				}
			}
			restore(old);
			return v;
		case EField(e,f,fields):
			canUseAbs = true;
			if( improvedField && fields != null && fields.length > 1 )
			{
				var r = findField(fields);
				if( r != null )
					return r;
			}
			var r = get(expr(e),f);
			canUseAbs = false;
			return r;
		case ESwitchBinop(p, e1, e2):
			var parent = expr(p);
			var e1 = expr(e1), e2 = expr(e2);
			if( parent == e1 )
				return e1;
			else if( parent == e2 )
				return e2;
			return null;
		case EBinop(op,e1,e2):
			var fop = binops.get(op);
			if( fop == null ) error(EInvalidOp(op));
			return fop(e1,e2);
		case EUnop(op,prefix,e):
			switch(op) {
			case "!":
				var e:Null<Dynamic> = expr(e);
				if( e != null && !Std.isOfType(Bool,e) )
					error(ECustom(Tools.checkType(e,Bool)));
				return !e;
			case "-":
				var e:Null<Dynamic> = expr(e);
				if( e != null && !Std.isOfType(Int,e) )
					error(ECustom(Tools.checkType(e,Int)));
				return -e;
			case "++":
				return increment(e,prefix,1);
			case "--":
				return increment(e,prefix,-1);
			case "~":
				var e:Null<Dynamic> = expr(e);
				if( e != null && !Std.isOfType(Int,e) )
					error(ECustom(Tools.checkType(e,Int)));
				#if(neko && !haxe3)
				return haxe.Int32.complement(e);
				#else
				return ~e;
				#end
			default:
				error(EInvalidOp(op));
			}
		case ECall(e,params):
			var args = new Array();
			for( p in params )
			{
				args.push(expr(p));
			}
			
			switch( Tools.expr(e) ) {
			case EField(e,f,fields):
				strictVar = true;
				var r = null;
				if( improvedField && fields != null && fields.length > 1 )
					r = findField(fields,"op");

				var obj = r != null ? r : expr(e);
				strictVar = false;
				if( obj == null ) error(EInvalidAccess(f));
				return fcall(obj,f,args);
			default:
				strictVar = true;
				var e = expr(e);
				strictVar = false;
				return call(null,e,args);
			}
		case EIf(econd,e1,e2):
			strictVar = true;
			inBool = true;
			var econd = expr(econd);
			checkBool(econd, "if");
			inBool = false;
			strictVar = false;
			return if( econd ) expr(e1) else if( e2 == null ) null else expr(e2);
		case EWhile(econd,e):
			if( strictVar ) return error(EUnexpected("while"));
			whileLoop(econd,e);
			return null;
		case EDoWhile(econd,e):
			if( strictVar ) return error(EUnexpected("do"));
			doWhileLoop(econd,e);
			return null;
		case EFor(v,v2,it,e):
			forLoop(v,v2,it,e);
			return null;
		case EBreak:
			throw SBreak;
		case EContinue:
			throw SContinue;
		case EReturnEmpty:
			if(inFunc) {
				shouldAbort = true;
				return null;
			} else 
			return error(EUnexpected("return"));
		case EReturn(e):
			returnValue = e == null ? null : expr(e);
			throw SReturn;
		case EImportStar(pkg):
			pkg = pkg.trim();
			var c = Type.resolveClass(pkg);
			var en = Type.resolveEnum(pkg);
			if( c != null )
			{
				var fields = Reflect.fields(c);
				for( field in fields )
				{
					var f = Reflect.getProperty(c,field);
					if( f != null )
						finalVariables.set(field,f);
				}
			}
			else if( en != null ) 
			{
				var f = Reflect.fields(en);
				for( field in f )
				{
					var f = Reflect.field(en, field);
					if( f != null ) 
						finalVariables.set(field,f);
				}
			}
			else 
			{
				#if(!macro && !DISABLED_MACRO_SUPERLATIVE)
				var map = @:privateAccess Tools.allClassesAvailable;
				var cl = new Map<String, Class<Dynamic>>();
				for( i => k in map )
				{
					var length = pkg.split('.');
					var length2 = i.split('.');
					
					if( length.length == length2.length )
						continue;
					if( length.length + 1 != length2.length )
						continue;

					var hasSamePkg = true;
					for( i in 0...length.length )
					{
						if(length[i] != length2[i])
						{
							hasSamePkg = false;
							break;
						}
					}
					if( hasSamePkg )
						cl[length2[length2.length - 1]] = k;
				}

				for( i => k in cl )
					finalVariables[i] = k;
				#end
			}

			return if( strictVar ) error(EUnexpected("import")) else null;
		case EImport( e , c , asIdent , f ):
			var og = c;
			if( asIdent != null )
				c = asIdent;
			if( c != null && e != null )
				finalVariables.set(c,e);
			if( e == null && STATICPACKAGES.exists(og) )
			{
				f = null;
				for( i => k in STATICPACKAGES[og].tea.fields )
					variables.set(i, k.v);
			}
			if( e == null && f != null )
				error(ETypeNotFound(f));
				
			return if( strictVar ) error(EUnexpected("import")) else null;
		case EUsing( e, c ):
			if( c != null && e != null )
				finalVariables.set( c , e );

			return if( strictVar ) error(EUnexpected("using")) else null;
		case EPackage(p):
			if( p == null )
				error(EUnexpected("package"));

			@:privateAccess script.setPackagePath(p);
			return if( strictVar ) error(EUnexpected("package")) else null;
		case EFunction(params,fexpr,name,_,line):
			var capturedLocals = duplicate(locals);
			var me = this;
			var hasOpt = false, minParams = 0;
			for( p in params )
				if( p.opt )
					hasOpt = true;
				else if( p.value == null )
					minParams++;
			var f = function(args:Array<Dynamic>) 
			{			
				function error(expr)
				{
					curExpr = og;
					if( line != null )
						curExpr.line = line;

					var me = this;
					me.error(expr);
				}

				if( args == null ) error(ENullObjectReference);
 				var copyArgs:Array<Dynamic> = [];
				inFunc = true;
				var i = 0;
				while( true ) {
					if( i < args.length ) {
						var v = args[i];
						if( v == null ) copyArgs.push(Not_NULL);
						else copyArgs.push(v);
						i++;
						if( i >= args.length ) break;
 					}
					else break;
				}
				if( copyArgs.length > params.length ) 
					error(ECustom("Too many arguments"));
					
				for( i in 0...params.length ) {
					var param = params[i];
					
					var arg:Dynamic = copyArgs[i];
					if( param == null ) continue;
					if( param.opt ) {
						if( ( arg == Not_NULL || arg == null ) && param.value != null )
							args[i] = expr(param.value);
						else if( arg == null && param.value == null )
							args[i] = null; 
					}
					else {
						if( arg == null && param.value == null ) {
							var str = "Not enough arguments, expected ";
							str += param.name;
							error(ECustom(str));
						}
						else if( arg == null && param.value != null )
							args[i] = expr(param.value);
					}
				}
			
				var old = me.locals, depth = me.depth;
				me.depth++;
				me.locals = me.duplicate(capturedLocals);
				for( i in 0...params.length )
				{
					currentArg = params[i].name;
					me.locals.set(params[i].name,{ r : {args[i];}});
				}
				var r = null;
				var oldDecl = declared.length;
				if( inTry )
					try {
						r = me.exprReturn(fexpr);
					} catch( e : Dynamic ) {
						me.locals = old;
						me.depth = depth;
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else{
					r = me.exprReturn(fexpr);
				}
				restore(oldDecl);
				me.locals = old;
				me.depth = depth;
				inFunc = false;
				if( returnedNothing )
				{
					if( strictVar )
						error(ECustom('Void should be Dynamic'));
				}
				else 
					returnedNothing = true;
				return r;
			};
			var oldf = f;
			var f = Reflect.makeVarArgs(f);
			if( name != null ) {
				if( depth == 0 ) {
					// global function
					finalVariables.set(name,f);
					if( inStatic )
					{
						if( script.classPath != null && script.classPath.length > 0 && STATICPACKAGES.exists(script.classPath) )
							STATICPACKAGES.get(script.classPath).tea.fields.set(name,TeaClass.createSugar(inPublic && !noPrivateAccess , f , false , false , true));
						else if( inPublic ) 
						{
							if( !pushedVars.contains(name) ) {
								pushedVars.push(name);
								SScript.globalVariables.set(name,f);
							}
						}
					}
				} else {
					// function-in-function is a local function
					declared.push( { n : name, old : locals.get(name) } );
					var ref = { r : f };
					locals.set(name, ref);
					capturedLocals.set(name, ref); // allow self-recursion
				}
			}
			return f;
		case EArrayDecl(arr):
			if( arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _)) ) {
				var isAllString:Bool = true;
				var isAllInt:Bool = true;
				var isAllObject:Bool = true;
				var isAllEnum:Bool = true;
				var keys:Array<Dynamic> = [];
				var values:Array<Dynamic> = [];
				for( e in arr ) {
					switch(Tools.expr(e)) {
						case EBinop("=>", eKey, eValue): {
							var key:Dynamic = expr(eKey);
							var value:Dynamic = expr(eValue);
							isAllString = isAllString && (key is String);
							isAllInt = isAllInt && (key is Int);
							isAllObject = isAllObject && Reflect.isObject(key);
							isAllEnum = isAllEnum && Reflect.isEnumValue(key);
							keys.push(key);
							values.push(value);
						}
						default: throw("=> expected");
					}
				}
				var map:Dynamic = {
					if(isAllInt) new haxe.ds.IntMap<Dynamic>();
					else if(isAllString) new haxe.ds.StringMap<Dynamic>();
					else if(isAllEnum) new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
					else if(isAllObject) new haxe.ds.ObjectMap<Dynamic, Dynamic>();
					else new Map<Dynamic, Dynamic>();
				}
				for( n in 0...keys.length ) {
					setMapValue(map, keys[n], values[n]);
				}
				return map;
			}
			else {
				var a = new Array();
				for( e in arr ) {
					a.push(expr(e));
				}
				return a;
			}
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if(isMap(arr)) {
				return getMapValue(arr, index);
			}
			else {
				return arr[index];
			}
		case ENew(cl,params):
			var a = new Array();
			for( e in params )
				a.push(expr(e));

			return cnew(cl,a);
		case EThrow(e):
			throw expr(e);
		case ETry(e,n,_,ecatch):
			var old = declared.length;
			var oldTry = inTry;
			try {
				inTry = true;
				var v : Dynamic = expr(e);
				restore(old);
				inTry = oldTry;
				return v;
			} catch( err : Stop ) {
				inTry = oldTry;
				throw err;
			} catch( err : Dynamic ) {
				// restore vars
				restore(old);
				inTry = oldTry;
				// declare 'v'
				declared.push({ n : n, old : locals.get(n) });
				locals.set(n,{ r : err });
				var v : Dynamic = expr(ecatch);
				restore(old);
				return v;
			}
		case EObject(fl):
			var o = {};
			for( f in fl )
				set(o,f.name,expr(f.e));
			return o;
		case ECoalesce(e1,e2,assign):
			return if( assign ) coalesce2(e1,e2) else coalesce(e1,e2);
		case ESafeNavigator(e1, f):
			var e = expr(e1);
			if( e == null )
			 	return null;

			return get(e,f);
		case ETernary(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else expr(e2);
		case ESwitch(e, cases, def):
			var val : Dynamic = expr(e);
			var match = false;
			for( c in cases ) {
				for( v in c.values )
				{
					if( ( !Type.enumEq(Tools.expr(v),EIdent("_")) && expr(v) == val ) && ( c.ifExpr == null || expr(c.ifExpr) == true ) ) {
						match = true;
						break;
					}
				}
				if( match ) {
					val = expr(c.expr);
					break;
				}
			}
			if( !match )
				val = def == null ? null : expr(def);
			return val;
		case EMeta(dot,n,args,e):
			var emptyExpr = false;
			if( e == null ) emptyExpr = true;
			if(n == "privateAccess")
				hasPrivateAccess = true;
			else if(n == "noPrivateAccess")
				noPrivateAccess = false;
			var e = if( emptyExpr ) null else expr(e);
			if( n == "privateAccess" )
				hasPrivateAccess = false;
			else if( n == "noPrivateAccess" )
				noPrivateAccess = false;
			return if( emptyExpr && strictVar ) error(ECustom("Excepted expression")) else e;
		case ECheckType(e,_):
			return expr(e);
		}
		return null;
	}

	function doWhileLoop(econd,e) {
		var old = declared.length;
		strictVar = true;
		inBool = true;
		var ec : Dynamic = expr(econd);
		checkBool(ec,"do while");
		inBool = false;
		do {
			try {
				expr(e);
			} catch( err : Stop ) {
				switch(err) {
				case SContinue:
				case SBreak: break;
				case SReturn: throw err;
				}
			}
			inBool = true;
			ec = expr(econd);
			inBool = false;
		}
		while( ec );
		strictVar = false;
		restore(old);
	}

	function whileLoop(econd,e) {
		var old = declared.length;
		strictVar = true;
		inBool = true;
		var ec : Dynamic = expr(econd);
		checkBool(ec);
		inBool = false;
		while( ec ) {
			try {
				expr(e);
			} catch( err : Stop ) {
				switch(err) {
				case SContinue:
				case SBreak: break;
				case SReturn: throw err;
				}
			}
			ec = expr(econd);
			checkBool(ec);
		}
		strictVar = false;
		restore(old);
	}

	function checkBool(ec : Dynamic , type = "while") : Void
	{
		if( ec != null && !Std.isOfType(ec, Bool) ) {
			var n = Type.getEnumName(ec);
			if( n == null ) n = Type.getClassName(ec);
			if( n == null ) {
				if( Std.isOfType(ec,Int) )
					n = 'Int';
				else if( Std.isOfType(ec,Float) )
					n = 'Float';
				else if( Std.isOfType(ec,String) )
					n = 'String';
				else if( Std.isOfType(ec,Array) )
					n = 'Array';
			}
			if( n != null ) error(ECustom(n + ' should be Bool'));
			else error(ECustom('Invalid $type expression (should be Bool)'));
		}
	}

	function findField(fields : Array<String> , ?mode : String , ?setProp : String , ?val:Dynamic ) : Dynamic 
	{
		var f = fields[0];
		if( f != null && (try resolve(f) catch(e) null) == null )
		{
			var fieldCl:Dynamic = null;
			var cls = [f];
			for( e in 1...fields.length )
			{
				cls.push(fields[e]);

				var cl = cls.join('.');
				var c = Tools.resolve(cl);
				if( c != null )
				{
					fieldCl = c;
					break;
				}
			}

			
			if( fieldCl != null )
			{
				if( cls.length != fields.length )
					for( i in cls.length + (setProp == null && mode != 'op' ? 0 : 1)...fields.length ) {
						var field = fields[i];
						fieldCl = Reflect.getProperty(fieldCl,field);
					}
			}

			if( fieldCl == null )
				return null;

			if( mode == null )
				return fieldCl;
			else if( mode == "set" )
			{
				Reflect.setProperty(fieldCl,setProp,val);
				return val;
			}
			else if( mode == 'op' ) 
				return fieldCl;
			else	
				return null;
		}
		else 
			return null;
	}

	function makeIterator( v : Dynamic ) : Iterator<Dynamic> {
		if( v is IMap )
			return new haxe.iterators.MapKeyValueIterator(v);

		#if((flash && !flash9) || (php && !php7 && haxe_ver < '4.0.0'))
		if( v.iterator != null ) v = v.iterator();
		#else
		if( v.iterator != null ) try v = v.iterator() catch( e : Dynamic ) {};
		#end
		if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
		return cast v;
	}

	function forLoop(n,n2,it,e) {
		var old = declared.length;
		declared.push({ n : n, old : locals.get(n) });
		if( n2 != null )
			declared.push({ n : n2, old : locals.get(n2) });
		strictVar = true;
		var it = makeIterator(expr(it));
		while( it.hasNext() ) {
			var next = it.next();
			var key = next;
			if( !Reflect.hasField(next,"key") && !Reflect.hasField(next,"value") && n2 != null )
			{
				error(ECustom(Tools.resolveType(next) + " has no field key"));
			}
			if( Reflect.hasField(next,"key") )
			{
				if( n2 == null )
					key = Reflect.getProperty(next,"value");
				else
					key = Reflect.getProperty(next,"key");
			}

			locals.set(n,{ r : key });
			if( Reflect.hasField(next,"value") && n2 != null )
				locals.set(n2,{ r : Reflect.getProperty(next,"value") });
			try {
				expr(e);
			} catch( err : Stop ) {
				switch( err ) {
				case SContinue:
				case SBreak: break;
				case SReturn: throw err;
				}
			}
		}
		strictVar = false;
		restore(old);
	}

	static inline function isMap(o:Dynamic):Bool {
		var classes:Array<Dynamic> = ["Map", "StringMap", "IntMap", "ObjectMap", "HashMap", "EnumValueMap", "WeakMap"];
		if(classes.contains(o))
			return true;

		return Std.isOfType(o, IMap);
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
	}

	function get( o : Dynamic, f : String ) : Dynamic {
		if( o == null ) error(EInvalidAccess(f));
		return {
			for( i => k in STATICPACKAGES )
				if( k.tea == o ) {
					var v = k.tea.fields.get(f);
					if( v == null )
						error(EDoNotHaveField(k.tea,f));
					if( !v.isPublic && (v.noAccess || !hasPrivateAccess ) )
						error(EPrivateField(f));
					return v.v;
				}

			for( i => k in EABSTRACTS ) 
				if( k.tea == o ) {
					var v = k.tea.fields[f];
					if( v == null )
						error(EAbstractField(k.tea,f));
					if( !v.isPublic && !hasPrivateAccess )
						error(EPrivateField(f));
					return v.v;
				}

			Reflect.getProperty(o,f);
		}
	}

	function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
		if( o == null ) error(EInvalidAccess(f));
		for( i => k in STATICPACKAGES )
			if( k.tea == o ) {
				var field = k.tea.fields.get(f);
				if( field == null )
					error(EDoNotHaveField(k.tea,f));
				if( !field.isPublic && (field.noAccess || !hasPrivateAccess ) )
					error(ECustom('Cannot access private field ' + f));
				if( field.isFinal )
					error(EInvalidFinal(f));
				if( field.isFun )
					error(EFunctionAssign(f));
				
				field.v = v;
				return v;
			}
		
		for( i => k in EABSTRACTS )
			if( k == o ) error(EWriting);

		Reflect.setProperty(o,f,v);
		return v;
	}

	function fcall( o : Dynamic, f : String, args : Array<Dynamic>) : Dynamic {
		return call(o, get(o, f), args);
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic>) : Dynamic {
		return Reflect.callMethod(o,f,args);
	}

	function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
		var c : Dynamic = try resolve(cl) catch(e) null;
		if( c == null ) c = Type.resolveClass(cl);
		if( c == null ) error(EInvalidAccess(cl));

		return Type.createInstance(c,args);
	}
}
