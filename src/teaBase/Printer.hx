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
import teaBase.Expr;

@:access(teaBase.Tools)
@:access(teaBase.TeaClass)
@:access(teaBase.TeaEAbstract)
@:keep
class Printer {
	public static function errorToString( e : Expr.Error ) {
		var message = switch( e.e ) {
			case ENullObjectReference: "Null Object Reference";
			case ETypeName: "Type name should start with an uppercase letter";
			case EDuplicate(v): "Duplicate class field declaration (" + v + ").";
			case EInvalidChar(c): "Invalid character: '"+(StringTools.isEof(c) ? "EOF" : String.fromCharCode(c))+"' ("+c+")";
			case EUnexpected(s): "Unexpected " + s;
			case EFunctionAssign(f): "Cannot rebind this method";
			case EUnterminatedString: "Unterminated string";
			case EUnterminatedComment: "Unterminated comment";
			case EInvalidPreprocessor(str): "Invalid preprocessor (" + str + ")";
			case EUnknownVariable(v): "Unknown variable: "+v;
			case EInvalidIterator(v): "Invalid iterator: "+v;
			case EInvalidOp(op): "Invalid operator: "+op;
			case EInvalidAccess(f): "Invalid access to field " + f;
			case EInvalidAssign: "Invalid assign";
			case ETypeNotFound(t): 
				var str = "Type not found : " + t;
				#if (!macro && !DISABLED_MACRO_SUPERLATIVE)
				var split = t.split('.');
				var similarNames:Array<Array<Dynamic>> = [];
				var allNames = Tools.allNamesAvailable;
				for( i in allNames ) {
					var same = 0;
					var names = i.split('.');
					for( i in 0...names.length ) {
						var nameSplit = try names[i].split('') catch( e ) [];
						var splitSplit = try split[i].split('') catch( e ) [];
						var length = nameSplit.length;
						if( splitSplit.length < nameSplit.length ) length = splitSplit.length;
						for( i in 0...length ) {
							if( nameSplit[i] == splitSplit[i] && nameSplit[i] != '' ) 
								same++;
						}
					}	
					if( same > 0 )
						similarNames.push([same, i]);
				}
				if( similarNames.length > 0 ) {
					var num = 0;
					var biggest:Array<Dynamic> = [];
					for( i in similarNames ) {
						if( i[0] > num || ( i[0] == num && biggest[1].length < num ) ) {
							num = i[0];
							biggest = i;
						}
					}
					str += "\nDid you mean ? " + biggest[1];
				}
				#end
				str;
			case EWriting: "This expression cannot be accessed for writing";
			case EUnmatchingType(v,t,n): t + " should be " + v + "" + if(n != null) ' for variable "$n".' else ".";
			case ECustom(msg): msg;
			case EInvalidFinal(v): "This expression cannot be accessed for writing";
			case EDoNotHaveField(cl, f): cl + " has no field " + f;
			case EAbstractField(abs,f): "Abstract<" + abs.name + "> has no field " + f;
			case EUnexistingField(f,f2): f2 + " has no field " + f;
			case EPrivateField(f): "Cannot access private field " + f;
			case EUnknownIdentifier(v): "Unknown identifier: "  + v + ".";
			case EUpperCase: "Package name cannot have capital letters.";
			case ECannotUseAbs: "Cannot use abstract as value";
			case EAlreadyModule(m,tea) | EMultipleDecl(m,tea): 
				var str = if( Type.enumEq(e.e,EMultipleDecl(m,tea)) ) "Multiple class declaration " + m else "Name " + m + " is already defined in this module";
				if( tea != null )
				{
					str += "\n" + tea;
					var str2 = "";
					for( i in 0...tea.length )
						str2 += "^";
					str += "\n" + str2 + " Previous declaration here";
				}
				str;
			case ESuper: "Cannot use super as value";
		};
		var str = e.origin + ":" + e.line + ": " + message;
		return str;
	}
}
