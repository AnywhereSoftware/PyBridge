B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public BuiltIns As PyWrapper
	Public EvalGlobals As PyWrapper
	Public Sys As PyWrapper
	Private mBridge As PyBridge
	Private RegisteredMembers As B4XSet
End Sub

Public Sub Initialize (bridge As PyBridge, obj As PyObject)
	mBridge = bridge
	BuiltIns.Initialize(mBridge, obj)
	Sys = mBridge.ImportLib.ImportModule("sys")
	EvalGlobals = BuiltIns.Run("dict", Null)
	RegisteredMembers.Initialize
End Sub

Public Sub Print (Obj As Object)
	BuiltIns.Run("print", Array(Obj))
End Sub

Public Sub RegisterMember (KeyName As String, ClassCode As String, Overwrite As Boolean)
	If RegisteredMembers.Contains(KeyName) = False Or Overwrite Then
		BuiltIns.Run("exec", Array(ClassCode, EvalGlobals, Null))
		RegisteredMembers.Add(KeyName)
	End If
End Sub

Public Sub RunCode (MemberName As String, Args As List, FunctionCode As String) As PyWrapper
	RegisterMember(MemberName, FunctionCode, False)
	Return GetMember(MemberName).Run2("__call__", Args, Null)
End Sub

Public Sub GetMember(Member As String) As PyWrapper
	Return EvalGlobals.Run("__getitem__", Array(Member))
End Sub

