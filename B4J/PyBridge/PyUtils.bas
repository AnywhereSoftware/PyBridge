B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#ModuleVisibility: B4XLib
Sub Class_Globals
	Public TASK_TYPE_RUN = 1, TASK_TYPE_GET = 2, TASK_TYPE_RUN_ASYNC = 3, TASK_TYPE_CLEAN = 4 _
		, TASK_TYPE_ERROR = 5, TASK_TYPE_EVENT = 6, TASK_TYPE_PING = 7, TASK_TYPE_FLUSH = 8 As Int
	
	Public PythonBridgeCodeVersion As String = "0.12"
	Public PyOutPrefix = "(pyout) ", PyErrPrefix = "(pyerr) ", B4JPrefix = "(b4j) " As String
	Public EvalGlobals As PyWrapper
	Public ImportLib As PyWrapper
	
	Private mBridge As PyBridge
	Public TaskIdCounter, PyObjectCounter As Int
	Public CleanerClass As String
	Public CleanerIndex As Int
	Public Comm As PyComm
	Public mOptions As PyOptions
	Public cleaner As JavaObject
	Public RegisteredMembers As B4XSet
End Sub

'Internal method
Public Sub Initialize (bridge As PyBridge, vComm As PyComm)
	mBridge = bridge
	CleanerClass = GetType(Me) & "$CleanRunnable"
	cleaner = cleaner.InitializeStatic("java.lang.ref.Cleaner").RunMethod("create", Null)
	If GetSystemProperty("b4j.ide", False) = True Then
		PyErrPrefix = ""
		PyOutPrefix = ""
		B4JPrefix = ""
	End If
End Sub

Public Sub Connected (vImportLib As PyObject, options As PyOptions)
	mOptions = options
	ImportLib.Initialize(mBridge, vImportLib)
	EvalGlobals = mBridge.Builtins.Run("dict")
	PyObjectCounter = 100
	RegisteredMembers.Initialize
	CheckKeysNeedToBeCleaned
End Sub

Public Sub Disconnected
	CleanerIndex = CleanerIndex + 1
End Sub


'Use PyWrapper.Run instead.
Public Sub Run (Target As PyObject, Method As String, Args As InternalPyMethodArgs) As PyObject
	Dim res As PyObject = CreatePyObject(0)
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN, _
		Array(Target.Key, Method, Args.Args, Args.KWArgs, res.Key))
	Comm.SendTask(TASK)
	Return res
End Sub


'Use PyWrapper.RunAsync instead.
Public Sub RunAsync(Target As PyObject, Method As String, Args As InternalPyMethodArgs) As ResumableSub
	Dim res As PyObject = CreatePyObject(0)
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN_ASYNC, Array(Target.Key, Method, Args.Args, Args.KWArgs, res.Key))
	Comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, res)
End Sub

Public Sub UnwrapBeforeSerialization (Extra As List)
	UnwrapList(Extra.Get(2))
	UnwrapMap(Extra.Get(3))
End Sub

Private Sub UnwrapList (Lst As List)
	If NotInitialized(Lst) Then Return
	For i = 0 To Lst.Size - 1
		Dim v As Object = Lst.Get(i)
		If v Is PyWrapper Then
			Lst.Set(i, v.As(PyWrapper).InternalKey)
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
			Obj(i) = o.As(PyWrapper).InternalKey
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
	If NotInitialized(Map) Then Return
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
		Map.Put(key, value.As(PyWrapper).InternalKey)
	Next
End Sub

Public Sub Flush As ResumableSub
	Dim task As PyTask = CreatePyTask(0, TASK_TYPE_FLUSH, Array())
	Comm.SendTaskAndWait(task)
	Wait For (task) AsyncTask_Received (task As PyTask)
	Return True
End Sub

'Use PyWrapper.Fetch instead.
Public Sub Fetch(PyObject As PyObject) As ResumableSub
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_GET, Array(PyObject.Key))
	Comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, PyObject)
End Sub

'Used internally.
Public Sub PyLog(Prefix As String, Clr As Int, O As Object)
	#if not(DISABLE_PYBRIDGE_LOGS)
	If o Is PyWrapper Then
		mBridge.Print(o, Clr = mOptions.PyErrColor)
	Else
		Dim s As String = o
		s = s.Trim.Replace(Chr(13), "")
		If s.Length = 0 Then Return
		If Clr <> 0 Then
			LogColor(Prefix & s, Clr)
		Else
			Log(Prefix & s.Trim)
		End If
	End If
	#End If
End Sub

'Internal method
Public Sub CreatePyTask (TaskId As Int, TaskType As Int, Extra As List) As PyTask
	Dim t1 As PyTask
	t1.Initialize
	If TaskId = 0 Then
		TaskIdCounter = TaskIdCounter + 1
		TaskId = TaskIdCounter
	End If
	t1.TaskId = TaskId
	t1.TaskType = TaskType
	t1.Extra = Extra
	Return t1
End Sub

Public Sub CreatePyObject (Key As Int) As PyObject
	Dim t1 As PyObject
	t1.Initialize
	If Key = 0 Then
		PyObjectCounter = PyObjectCounter + 1
		Key = PyObjectCounter
	End If
	t1.Key = Key
	RegisterForCleaning(t1)
	Return t1
End Sub


Private Sub CheckForErrorsAndReturn (TASK As PyTask, PyObject As PyObject) As InternalPyTaskAsyncResult
	If TASK.TaskType = TASK_TYPE_ERROR Then
		PyLog(B4JPrefix, mOptions.PyErrColor, TASK.Extra.Get(0))
	End If
	Return CreateInternalPyTaskAsyncResult(PyObject, TASK.Extra.Get(0), TASK.TaskType == TASK_TYPE_ERROR)
End Sub


Private Sub RegisterForCleaning (Py As PyObject)
	Dim Runnable As JavaObject
	Runnable.InitializeNewInstance(CleanerClass, Array(Py.Key))
	cleaner.RunMethod("register", Array(Py, Runnable))
End Sub

Private Sub CheckKeysNeedToBeCleaned
	Dim c As JavaObject
	c.InitializeStatic(CleanerClass)
	c.RunMethod("getKeys", Null) 'clear any previous keys
	CleanerIndex = CleanerIndex + 1
	Dim MyIndex As Int = CleanerIndex
	Do While MyIndex = CleanerIndex
		Dim keys As List = c.RunMethod("getKeys", Null)
		If keys.Size > 0 Then
			Comm.SendTask(CreatePyTask(0, TASK_TYPE_CLEAN, keys))
		End If
		Sleep(1000)
	Loop
End Sub


#if Java
public static class CleanRunnable implements Runnable {
	private final int key;
	private final static java.util.List<Object> listOfKeys = java.util.Collections.synchronizedList(new java.util.ArrayList<Object>());
	public CleanRunnable(int key) {
		this.key = key;
	}
	public void run() {
		listOfKeys.add(key);
	}
	public static java.util.List<Object> getKeys() {
		synchronized(listOfKeys) {
			java.util.ArrayList<Object> res = new java.util.ArrayList<Object>(listOfKeys);
			listOfKeys.clear();
			return res;
		}
	}
}

#End If

Private Sub CreateInternalPyTaskAsyncResult (PyObject As PyObject, Value As Object, Error As Boolean) As InternalPyTaskAsyncResult
	Dim t1 As InternalPyTaskAsyncResult
	t1.Initialize
	t1.PyObject = PyObject
	t1.Value = Value
	t1.Error = Error
	Return t1
End Sub

Public Sub DetectOS As String
	Dim os As String = GetSystemProperty("os.name", "").ToLowerCase
	If os.Contains("win") Then
		Return "windows"
	Else If os.Contains("mac") Then
		Return "mac"
	Else
		Return "linux"
	End If
End Sub
