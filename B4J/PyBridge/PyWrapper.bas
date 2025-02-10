B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public InternalKey As PyObject
	Private mBridge As PyBridge
	Private mFetched As Boolean
	Private mError As Boolean
	Private mValue As Object
	Private LastArgs As InternalPyMethodArgs
End Sub

'Internal method.
Public Sub Initialize (Bridge As PyBridge, Key As PyObject)
	InternalKey = Key
	mBridge = Bridge
End Sub



Public Sub Run(Method As String) As PyWrapper
	Return RunArgs(Method, Null, Null)
End Sub

Public Sub Args(Parameters As List) As PyWrapper
	LastArgs.Args.AddAll(Parameters)
	Return Me
End Sub

Public Sub Arg(Parameter As Object) As PyWrapper
	LastArgs.Args.Add(Parameter)
	Return Me
End Sub

Public Sub ArgNamed (Name As String, Parameter As Object) As PyWrapper
	LastArgs.KWArgs.Put(Name, Parameter)
	Return Me
End Sub

Public Sub ArgsNamed (Parameters As Map) As PyWrapper
	For Each k As String In Parameters.Keys
		LastArgs.KWArgs.Put(k, Parameters.Get(k))
	Next
	Return Me
End Sub

'Runs a method with the given positional and named arguments. Both can be Null.
Public Sub RunArgs (Method As String, PositionalArgs As List, NamedArgs As Map) As PyWrapper
	Dim a As InternalPyMethodArgs = PrepareArgs(PositionalArgs, NamedArgs)
	Dim py As PyObject = mBridge.Utils.run(InternalKey, Method, a)
	Dim w As PyWrapper
	w.Initialize(mBridge, py)
	w.LastArgs = a
	Return w
End Sub



'Fetches the value of a remote Python object. Avoid fetching values when possible. Fetching values requires waiting for the queue to be processed.
'<code>Wait For (PyWrapper1.Fetch) Complete (Result As PyWrapper)</code>
Public Sub Fetch As ResumableSub	
	Wait For (mBridge.Utils.Fetch(InternalKey)) Complete (Result As InternalPyTaskAsyncResult)
	Return Wrap(Result)
End Sub

'Returns a field (attribute) of this object. Note that its value is not fetched.
Public Sub GetField (Field As String) As PyWrapper
	Return mBridge.Builtins.RunArgs("getattr", Array(InternalKey, Field), Null)
End Sub

Private Sub PrepareArgs (Args1 As List, KWArgs As Map) As InternalPyMethodArgs
	Dim a As InternalPyMethodArgs
	a.Initialize
	a.Args = B4XCollections.CreateList(Args1)
	a.KWArgs = B4XCollections.MergeMaps(KWArgs, Null)
	Return a
End Sub
'Runs an async method.
'<code>Wait For (PyWrapper1.RunAsync("MethodName", Array("arg1"), Null) Complete (Result As PyWrapper)</code>
Public Sub RunAsync (Method As String, PositionalArgs As List, NamedArgs As Map) As ResumableSub
	Dim a As InternalPyMethodArgs = PrepareArgs(PositionalArgs, NamedArgs)
	Wait For (mBridge.Utils.RunAsync(InternalKey, Method, a)) Complete (Result As InternalPyTaskAsyncResult)
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

'Gets the fetched value. Will raise an exception if the value was not fetched yet, or if there was any error.
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

'Remotely prints the object.
Public Sub Print
	Print2("", "", False)
End Sub

Public Sub PrintError
	Print2("", "", True)
End Sub

'Similar to Print with an additional prefix and suffix strings, separated by spaces.
Public Sub Print2 (Prefix As String, Suffix As String, StdErr As Boolean)
	If mFetched Then
		Log(mValue)
	Else
		mBridge.Print(Array(Prefix, Me, Suffix), StdErr)
	End If
End Sub

'Same as getting an item from a collection using square brackets.
'Do not confuse with GetField which returns an attribute of this object.
Public Sub GetItem (Key As Object) As PyWrapper
	Return Run("__getitem__").Arg(mBridge.ConvertToIntIfMatch(Key))
End Sub

'Same as setting an item in a collection using square brackets.
Public Sub SetItem(Key As Object, Value As Object)
	Run("__setitem__").Arg(mBridge.ConvertToIntIfMatch(Key)).Arg(Value)
End Sub

'Same as deleting an item using the del keyword.
Public Sub DelItem(Key As Object, Value As Object) 
	Run("__detitem__").Arg(mBridge.ConvertToIntIfMatch(Key)).Arg(Value)
End Sub

'Tests whether the collection contains the item.
Public Sub Contains(Item As Object) As PyWrapper
	Return Run("__contains__").Arg(mBridge.ConvertToIntIfMatch(Item))
End Sub

'Returns a string representation of this object.
Public Sub Str As PyWrapper
	Return mBridge.Builtins.Run("str").Arg(InternalKey)
End Sub

'Returns the type of this object.
Public Sub TypeOf As PyWrapper
	Return mBridge.Builtins.Run("type").Arg(InternalKey)
End Sub

'Return the length of an object (if it supports it).
Public Sub Len As PyWrapper
	Return mBridge.Builtins.Run("len").Arg(InternalKey)
End Sub

'Returns the shape attribute (if it exists).
Public Sub Shape As PyWrapper
	Return GetField("shape")
End Sub

'Addition operator (+).
Public Sub OperAdd (Other As Object) As PyWrapper
	Return Run("__add__").Arg(Other)
End Sub

'Subtract operator (-).
Public Sub OperSub (Other As Object) As PyWrapper
	Return Run("__sub__").Arg(Other)
End Sub

'Multiply operator (*).
Public Sub OperMul (Other As Object) As PyWrapper
	Return Run("__mul__").Arg(Other)
End Sub

'Modulo operator (%).
Public Sub OperMod (Other As Object) As PyWrapper
	Return Run("__mod__").Arg(Other)
End Sub

'Power operator (**).
Public Sub OperPow (Other As Object) As PyWrapper
	Return Run("__pow__").Arg(Other)
End Sub

'Casts number to float.
Public Sub AsFloat As PyWrapper
	Return mBridge.Builtins.Run("float").Arg(InternalKey)
End Sub

'Casts number to int.
Public Sub AsInt As PyWrapper
	Return mBridge.Builtins.Run("int").Arg(Me)
End Sub

'Equal operator.
Public Sub OprEqual (Other As Object) As PyWrapper
	Return Run("__eq__").Arg(Other)
End Sub
'Not equal operator.
Public Sub OprNotEqual (Other As Object) As PyWrapper
	Return Run("__ne__").Arg(Other)
End Sub
'Less than operator.
Public Sub OprLess (Other As Object) As PyWrapper
	Return Run("__lt__").Arg(Other)
End Sub
'Less than or equal to operator.
Public Sub OprLessEqual (Other As Object) As PyWrapper
	Return Run("__le__").Arg(Other)
End Sub
'Greater than operator.
Public Sub OprGreater (Other As Object) As PyWrapper
	Return Run("__gt__").Arg(Other)
End Sub

'Greater than or equal to.
Public Sub OprGreaterEqual (Other As Object) As PyWrapper
	Return Run("__ge__").Arg(Other)
End Sub

'Non short circuit and operator (&).
Public Sub OprAnd (Other As Object) As PyWrapper
	Return Run("__and__").Arg(Other)
End Sub
'Non short circuit or opertaor (|).
Public Sub OprOr (Other As Object) As PyWrapper
	Return Run("__or__").Arg(Other)
End Sub


#if java
public void raiseError(String desc) {
	throw new RuntimeException (desc);
}
#End If