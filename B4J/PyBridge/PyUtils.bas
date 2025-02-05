B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public Builtins As PyWrapper
	Public InternalEvalGlobals As PyWrapper
	Public InternalImportLib As PyWrapper
	Public Sys As PyWrapper
	Private mBridge As PyBridge
	Private RegisteredMembers As B4XSet
	Private Epsilon As Double = 0.0000001
End Sub

'Internal method. use Py.Utils.
Public Sub Initialize (bridge As PyBridge, vBuiltIn As PyObject, vImportLib As PyObject)
	mBridge = bridge
	InternalImportLib.Initialize(mBridge, vImportLib)
	Builtins.Initialize(mBridge, vBuiltIn)
	Sys = ImportModule("sys")
	InternalEvalGlobals = Builtins.Run("dict", Null)
	RegisteredMembers.Initialize
End Sub

'Remotely prints the values or PyWrappers. Separated by space.
Public Sub Print (Objects As List)
	Dim Code As String = $"
def _print(obj):
	print(*obj)
"$
	RunCode("_print", Array(Objects), Code) 
End Sub

Private Sub RegisterMember (KeyName As String, ClassCode As String, Overwrite As Boolean)
	If RegisteredMembers.Contains(KeyName) = False Or Overwrite Then
		Builtins.Run("exec", Array(ClassCode, InternalEvalGlobals, Null))
		RegisteredMembers.Add(KeyName)
	End If
End Sub

'Runs a Python function or class. Note that the code is registered once and is then reused.
'It is recommended to use the "RunCode" code snippet that creates a sub that calls RunCode.
Public Sub RunCode (MemberName As String, Args As List, FunctionCode As String) As PyWrapper
	RegisterMember(MemberName, FunctionCode, False)
	Return GetMember(MemberName).Run2("__call__", Args, Null)
End Sub

'Runs the provided Python code. It runs using the same global namespace as RunCode.
Public Sub RunNoArgsCode (Code As String)
	Builtins.Run("exec", Array(Code, InternalEvalGlobals, Null))
End Sub

'Runs a single statement and returns the result (PyWrapper).
'Example: <code>Py.Utils.RunStatement("10 * 15").Print</code>
Public Sub RunStatement (Code As String) As PyWrapper
	Return RunStatement2(Code, Null)
End Sub
'Runs a single statement and returns the result (PyWrapper). Allows passing a map with a set of "local" variables.
'Example: <code>Py.Utils.RunStatement2($"locals()["x"] + 10"$, CreateMap("x": 20)).Print</code>
Public Sub RunStatement2 (Code As String, Locals As Map) As PyWrapper
	If IsNotInitialized(Locals) Then Locals = B4XCollections.GetEmptyMap
	Return Builtins.Run ("eval", Array(Code, InternalEvalGlobals, Locals))
End Sub

'Returns a member or attribute that was previously added to the global namespace.
Public Sub GetMember(Member As String) As PyWrapper
	Return InternalEvalGlobals.Run("__getitem__", Array(Member))
End Sub

'Imports a module.
Public Sub ImportModule (Module As String) As PyWrapper
	Return InternalImportLib.Run("import_module", Array(Module))
End Sub

'Creates a slice object from Start (inclusive) to Stop (exclusive). Pass Null to omit a value.
Public Sub Slice (Start As Object, Stop As Object) As PyWrapper
	Return Slice2(Start, Stop, Null)
End Sub

'Same as Slice with an additional step value. Note that the value can be negative to traverse the collection backward.
Public Sub Slice2 (Start As Object, Stop As Object, StepValue As Object) As PyWrapper
	Return Builtins.Run("slice", Array(ConvertToIntIfMatch(Start), ConvertToIntIfMatch(Stop), ConvertToIntIfMatch(StepValue)))
End Sub

'Utility to prevent ints being treated as floats.
Public Sub ConvertToIntIfMatch (o As Object) As Object
	If o Is Float Or o Is Double Then
		Dim d As Double = o
		Dim i As Int = d
		If Abs(d - i) < Epsilon Then Return i
	End If
	Return o
End Sub

