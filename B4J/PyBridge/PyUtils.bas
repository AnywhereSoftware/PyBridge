B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public BuiltIns As PyWrapper
	Public EvalGlobals As PyWrapper
	Public ImportLib As PyWrapper
	Public Sys As PyWrapper
	Private mBridge As PyBridge
	Private RegisteredMembers As B4XSet
End Sub

'Internal method. use Py.Utils.
Public Sub Initialize (bridge As PyBridge, vBuiltIn As PyObject, vImportLib As PyObject)
	mBridge = bridge
	ImportLib.Initialize(mBridge, vImportLib)
	BuiltIns.Initialize(mBridge, vBuiltIn)
	Sys = ImportModule("sys")
	EvalGlobals = BuiltIns.Run("dict", Null)
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
		BuiltIns.Run("exec", Array(ClassCode, EvalGlobals, Null))
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
	BuiltIns.Run("exec", Array(Code, EvalGlobals, Null))
End Sub

'Returns a member or attribute that was previously added to the global namespace.
Public Sub GetMember(Member As String) As PyWrapper
	Return EvalGlobals.Run("__getitem__", Array(Member))
End Sub

'Imports a module.
Public Sub ImportModule (Module As String) As PyWrapper
	Return ImportLib.Run("import_module", Array(Module))
End Sub

