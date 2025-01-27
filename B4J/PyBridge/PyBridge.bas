B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#Event: Connected
#Event: Disconnected
Sub Class_Globals
	Type PyObject (Key As Int)
	Private TASK_TYPE_RUN = 1, TASK_TYPE_GET = 2, TASK_TYPE_RUN_ASYNC = 3, TASK_TYPE_CLEAN = 4 _
		, TASK_TYPE_ERROR = 5 As Int
	Type PyTask (TaskId As Int, TaskType As Int, Extra As List)
	Type InternalPyTaskAsyncResult (PyObject As PyObject, Value As Object, Error As Boolean)
	Private cleaner As JavaObject
	Private comm As PyComm
	Private mCallback As Object
	Private mEventName As String
	Private CleanerClass As String
	Public Builtins As PyBuiltIns
	Public ImportLib As PyImport
	Private TaskIdCounter, PyObjectCounter As Int
	Private EmptyList As List, EmptyMap As Map
	Public Bridge As PyWrapper
End Sub

Public Sub Initialize (Callback As Object, EventName As String)
	cleaner = cleaner.InitializeStatic("java.lang.ref.Cleaner").RunMethod("create", Null)
	mCallback = Callback
	mEventName = EventName
	comm.Initialize(Me)
	CleanerClass = GetType(Me) & "$CleanRunnable"
	Bridge.Initialize(Me, CreatePyObject(1))
	ImportLib.Initialize(Me, CreatePyObject(2))
	Builtins.Initialize(Me, CreatePyObject(3))
	PyObjectCounter = 100
	EmptyList.Initialize
	EmptyMap.Initialize
	CheckKeysNeedToBeCleaned
End Sub

Private Sub CreatePyObject (Key As Int) As PyObject
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

Private Sub State_Changed (State As Int)
	CallSubDelayed(mCallback, mEventName & IIf(State = comm.STATE_CONNECTED, "_connected", "_disconnected"))
End Sub

Private Sub Task_Received(TASK As PyTask)
	Log("task received")
End Sub

Public Sub Run (Target As PyObject, Method As String, Args As List, KWArgs As Map) As PyObject
	Dim res As PyObject = CreatePyObject(0)
	If Args = Null Or Args.IsInitialized = False Then Args = EmptyList
	If KWArgs = Null Or KWArgs.IsInitialized = False Then KWArgs = EmptyMap
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN, _
		Array(Target.Key, Method, Args, KWArgs, res.Key))
	comm.SendTask(TASK)
	Return res
End Sub

Public Sub Flush
	comm.Flush
End Sub

Public Sub RunAsync(Target As PyObject, Method As String, Args As List, KWArgs As Map) As ResumableSub
	Dim res As PyObject = CreatePyObject(0)
	If Args = Null Or Args.IsInitialized = False Then Args = EmptyList
	If KWArgs = Null Or KWArgs.IsInitialized = False Then KWArgs = EmptyMap
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN_ASYNC, Array(Target.Key, Method, Args, KWArgs, res.Key))
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, res)
End Sub

Private Sub CheckForErrorsAndReturn (Task As PyTask, PyObject As PyObject) As InternalPyTaskAsyncResult
	If Task.TaskType = TASK_TYPE_ERROR Then
		MyLog(Task.Extra.Get(0))
	End If
	Return CreateInternalPyTaskAsyncResult(PyObject, Task.Extra.Get(0), Task.TaskType == TASK_TYPE_ERROR)
End Sub

Public Sub Fetch(PyObject As PyObject) As ResumableSub
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_GET, Array(PyObject.Key))
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, PyObject)
End Sub

Public Sub MyLog(s As String)
	#if not(DISABLE_PYBRIDGE_LOGS)
	Log("PyBridge: " & s)
	#End If
End Sub

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

Private Sub RegisterForCleaning (Py As PyObject)
	Dim Runnable As JavaObject
	Runnable.InitializeNewInstance(CleanerClass, Array(Py.Key))
	cleaner.RunMethod("register", Array(Py, Runnable))
End Sub

Private Sub CheckKeysNeedToBeCleaned
	Do While True
		Sleep(1000)
		Dim c As JavaObject
		Dim keys As List = c.InitializeStatic(CleanerClass).RunMethod("getKeys", Null)
		If keys.Size > 0 Then
			comm.SendTask(CreatePyTask(0, TASK_TYPE_CLEAN, keys))
		End If
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