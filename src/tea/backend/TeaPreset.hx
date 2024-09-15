package tea.backend;

enum TeaPresetMode
{
    NONE;
    MINI;
    REGULAR;
}

@:access(tea.backend.TeaPresetClasses)
@:access(tea.SScript)
class TeaPreset
{
    public var haxeMode:TeaPresetMode;

    var script:SScript;
    var _destroyed:Bool = false;
    public function new(script:SScript)
    {
        if (script == null || script._destroyed)
            return;

        this.script = script;
        haxeMode = SScript.defaultTeaPreset;
    }

    function preset()
    {
        if (_destroyed || script == null || script._destroyed)
            return;

        var hArray = switch haxeMode {
            case MINI: TeaPresetClasses.miniHaxe;
            case REGULAR: TeaPresetClasses.regularHaxe;
            case _: [];
        }

        for (i in hArray.copy())
            script.setClass(i);
    }

    function destroy()
    {
        if (_destroyed)
            return;

        script = null;
        haxeMode = null;

        _destroyed = true;
    }
}

class TeaPresetClasses 
{
    static var miniHaxe:Array<Class<Dynamic>> = [
        Date, DateTools, EReg, Math, Reflect, Std, StringTools, Type,
        #if sys Sys, sys.io.File, sys.FileSystem #end
    ];

    static var regularHaxe:Array<Class<Dynamic>> = {
        var array = miniHaxe.copy();
        var array2:Array<Class<Dynamic>> = [
            EReg, List, StringBuf, Xml,
            haxe.Http, haxe.Json, haxe.Log, haxe.Serializer, haxe.Unserializer, haxe.Timer,
            #if sys haxe.SysTools, sys.io.Process, sys.io.FileInput, sys.io.FileOutput, #end
        ];

        for (i in array2)
            array.push(i);

        array;
    }
}