B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public mKey As PyObject
	Private mBridge As PyBridge
End Sub

Public Sub Initialize (Bridge As PyBridge, Key As PyObject)
	mKey = Key
	mBridge = Bridge
End Sub

Public Sub Run (Method As String, Args As List) As PyWrapper
	Return Run2(Method, Args, Null)
End Sub

Public Sub Run2 (Method As String, Args As List, KWArgs As Map) As PyWrapper
	Return Wrap(mBridge.run(mKey, Method, Args, KWArgs))
End Sub

Public Sub FetchValue As ResumableSub
	Wait For (mBridge.Get(Array(mKey))) Complete (Values As List)
	Return Values.Get(0)
End Sub

Public Sub GetField (Field As String) As PyWrapper
	Return mBridge.BuiltinModule.Run("getattr", Array(mKey, Field))
End Sub

Public Sub RunAsync (Method As String, Args As List) As ResumableSub
	Wait For (mBridge.RunAsync(mKey, Method, Args, Null)) Complete (Result As PyObject)
	Return Wrap(Result)
End Sub

Public Sub RunAsync2 (Method As String, Args As List, KWArgs As Map) As ResumableSub
	Wait For (mBridge.RunAsync(mKey, Method, Args, KWArgs)) Complete (Result As PyObject)
	Return Wrap(Result)
End Sub

Private Sub Wrap (Key As PyObject) As PyWrapper
	Dim w As PyWrapper
	w.Initialize(mBridge, Key)
	Return w
End Sub