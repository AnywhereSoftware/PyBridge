B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public mKey As PyObject
	Private mBridge As PyBridge
	Private mFetched As Boolean
	Private mError As Boolean
	Private mValue As Object
End Sub

Public Sub Initialize (Bridge As PyBridge, Key As PyObject)
	mKey = Key
	mBridge = Bridge
End Sub

Public Sub Run (Method As String, Args As List) As PyWrapper
	Return Run2(Method, Args, Null)
End Sub

Public Sub Run2 (Method As String, Args As List, KWArgs As Map) As PyWrapper
	UnwrapList(Args)
	UnwrapMap(KWArgs)
	Dim py As PyObject = mBridge.run(mKey, Method, Args, KWArgs)
	Dim w As PyWrapper
	w.Initialize(mBridge, py)
	Return w
End Sub

Private Sub UnwrapList (Lst As List)
	If Lst = Null Or Lst.IsInitialized = False Then Return
	For i = 0 To Lst.Size - 1
		Dim v As Object = Lst.Get(i)
		If v Is PyWrapper Then
			Lst.Set(i, v.As(PyWrapper).mKey)
		Else If v Is List Then
			UnwrapList(v)
		Else If v Is Map Then
			UnwrapMap(v)
		Else If IsArray(v) Then
			UnwrapTuple(v)
		End If
	Next
End Sub

Private Sub UnwrapTuple (Obj() As Object)
	For i = 0 To Obj.Length - 1
		Dim o As Object = Obj(i)
		If o Is PyWrapper Then
			Obj(i) = o.As(PyWrapper).mKey
		Else If o Is List Then
			UnwrapList(o)
		Else If o Is Map Then
			UnwrapMap(o)
		Else If IsArray(o) Then
			UnwrapTuple(o)
		End If
	Next
End Sub

Private Sub IsArray(obj As Object) As Boolean
	Return obj <> Null And "[Ljava.lang.Object;" = GetType(obj)
End Sub

Private Sub UnwrapMap (Map As Map)
	If Map = Null Or Map.IsInitialized = False Then Return
	Dim KeysThatNeedToBeUnwrapped As List
	KeysThatNeedToBeUnwrapped.Initialize
	For Each key As Object In Map.Keys
		Dim value As Object = Map.Get(key)
		If value Is PyWrapper Then
			KeysThatNeedToBeUnwrapped.Add(key)
		Else If value Is List Then
			UnwrapList(value)
		Else If value Is Map Then
			UnwrapMap(value)
		Else If IsArray(value) Then
			UnwrapTuple(value)
		End If
	Next
	For Each key As Object In KeysThatNeedToBeUnwrapped
		Dim value As Object = Map.Get(key)
		Map.Put(key, value.As(PyWrapper).mKey)
	Next
End Sub

Public Sub Fetch As ResumableSub	
	Wait For (mBridge.Fetch(mKey)) Complete (Result As InternalPyTaskAsyncResult)
	Return Wrap(Result)
End Sub

Public Sub GetField (Field As String) As PyWrapper
	Return mBridge.Utils.wrapper.Run("getattr", Array(mKey, Field))
End Sub

Public Sub RunAsync (Method As String, Args As List) As ResumableSub
	UnwrapList(Args)
	Wait For (mBridge.RunAsync(mKey, Method, Args, Null)) Complete (Result As InternalPyTaskAsyncResult)
	Return Wrap(Result)
End Sub

Public Sub RunAsync2 (Method As String, Args As List, KWArgs As Map) As ResumableSub
	UnwrapList(Args)
	UnwrapMap(KWArgs)
	Wait For (mBridge.RunAsync(mKey, Method, Args, KWArgs)) Complete (Result As InternalPyTaskAsyncResult)
	Return Wrap(Result)
End Sub

Private Sub Wrap (Result As InternalPyTaskAsyncResult) As PyWrapper
	Dim w As PyWrapper
	Dim key As PyObject = Result.PyObject
	Dim error As Boolean = Result.Error
	Dim value As Object = Result.Value
	w.Initialize(mBridge, key)
	w.mError = error
	w.mValue = value
	w.mFetched = True
	Return w
End Sub

Public Sub getValue As Object
	If mError Then
		Me.As(JavaObject).RunMethod("raiseError", Array(mValue))
	End If
	If mFetched = False Then
		Me.As(JavaObject).RunMethod("raiseError", Array("Value not fetched"))
	End If
	Return mValue
End Sub

Public Sub getIsFetched As Boolean
	Return mFetched
End Sub

#if java
public void raiseError(String desc) {
	throw new RuntimeException (desc);
}
#End If