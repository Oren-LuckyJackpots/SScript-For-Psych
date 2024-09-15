package teaBase;

@:access(teaBase.TeaClass)

typedef FieldSugar = {
    public var isPublic:Bool;
    public var v:Dynamic;
    public var isFinal:Bool;
    public var noAccess:Bool;
    public var isFun:Bool;
}

class TeaClass 
{
    public var name:String;
    public var fields:Map<String, FieldSugar> = [];
    public function new(name:String) this.name = name;

    public static function createSugar(isPublic:Bool, v:Dynamic, isFinal:Bool, noAccess:Bool, isFun:Bool):FieldSugar 
    {  
        return {isPublic: isPublic, v: v, isFinal: isFinal, noAccess: noAccess, isFun: isFun};
    }

    inline function toString():String 
        return "Class<" + name + ">";
}