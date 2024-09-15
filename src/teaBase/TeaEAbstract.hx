package teaBase;

typedef AbstractSugar = {
    public var isPublic:Bool;
    public var name:String;
    public var v:Dynamic;
}

class TeaEAbstract 
{
    var name:String;

    public static function createSugar(isPublic:Bool, name:String, v:Bool):AbstractSugar
        return {isPublic: isPublic, name: name, v: v};
    
    public var fields:Map<String, AbstractSugar> = new Map();

    public function new(name:String) 
    {
        this.name = name;
    }

    inline function toString():String
        throw "Cannot use abstract as value";
}