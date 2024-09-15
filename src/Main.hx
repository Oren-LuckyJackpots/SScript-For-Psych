import tea.SScript;

class Main {
    static function main() {
        var s = new SScript();
        s.doString("
        function e()
        {

        }
        
        return Math.random();");
        trace(s.returnValue);
    }
}