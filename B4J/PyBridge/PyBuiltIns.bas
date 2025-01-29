B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public Wrapper As PyWrapper
	Public EvalGlobals As PyWrapper
	Private mBridge As PyBridge
End Sub

Public Sub Initialize (bridge As PyBridge, obj As PyObject)
	mBridge = bridge
	Wrapper.Initialize(mBridge, obj)
	EvalGlobals = Wrapper.Run("dict", Null)
End Sub

Public Sub Print (Obj As Object)
	Wrapper.Run("print", Array(Obj))
End Sub

Public Sub RegisterClass (ClassCode As String)
	Wrapper.Run("exec", Array(ClassCode, EvalGlobals, Null))
End Sub

Public Sub RunFunction (FunctionCode As String)
	RegisterClass(FunctionCode)
End Sub

Public Sub GetMember(Member As String) As PyWrapper
	Return EvalGlobals.Run("__getitem__", Array(Member))
End Sub

