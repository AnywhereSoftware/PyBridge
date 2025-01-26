B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#Event: ConnectionStateChanged (Connected As Boolean)
Sub Class_Globals
	Type PyObject (Key As Int)
	Private TASK_TYPE_RUN = 1, TASK_TYPE_GET = 2, TASK_TYPE_RUN_ASYNC = 3, TASK_TYPE_CLEAN = 4 As Int
	Type PyTask (TaskId As Int, TaskType As Int, Extra As List)
	Private cleaner As JavaObject
	Private comm As PyComm
	Private mCallback As Object
	Private mEventName As String
	Private CleanerClass As String
	Public BridgeModule, ImportModule, BuiltinModule As PyWrapper
	Private TaskIdCounter, PyObjectCounter As Int
	Private EmptyList As List, EmptyMap As Map
	
End Sub

Public Sub Initialize (Callback As Object, EventName As String)
	cleaner = cleaner.InitializeStatic("java.lang.ref.Cleaner").RunMethod("create", Null)
	mCallback = Callback
	mEventName = EventName
	comm.Initialize(Me)
	CleanerClass = GetType(Me) & "$CleanRunnable"
	BridgeModule.Initialize(Me, CreatePyObject(1))
	ImportModule.Initialize(Me, CreatePyObject(2))
	BuiltinModule.Initialize(Me, CreatePyObject(3))
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
	CallSubDelayed2(mCallback, mEventName & "_ConnectionStateChanged", State = comm.STATE_CONNECTED)
End Sub

Private Sub Task_Received(TASK As PyTask)
	Log("task received")
End Sub

Public Sub Run (Target As PyObject, Method As String, Args As List, KWArgs As Map) As PyObject
	Dim res As PyObject = CreatePyObject(0)
	Dim aaa() As Object = ArrangeArgs(Args, KWArgs)
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN, Array(Target, Method, aaa(0), aaa(1), res))
	comm.SendTask(TASK)
	Return res
End Sub

Private Sub ArrangeArgs (Args As List, KWArgs As Map) As Object()
	If Args = Null Or Args.IsInitialized = False Then Args = EmptyList
	If KWArgs = Null Or KWArgs.IsInitialized = False Then KWArgs = EmptyMap
	If Args.Size > 0 Then
		Dim ConvertedArgs As List
		ConvertedArgs.Initialize
		For Each a As Object In Args
			ConvertedArgs.Add(IIf(a Is PyWrapper, a.As(PyWrapper).mKey, a))
		Next
		Args = ConvertedArgs
	End If
	If KWArgs.Size > 0 Then
		Dim ConvertedKWArgs As Map
		ConvertedKWArgs.Initialize
		For Each k As String In KWArgs.Keys
			Dim v As Object = KWArgs.Get(k)
			ConvertedKWArgs.Put(k, IIf(v Is PyWrapper, v.As(PyWrapper).mKey, v))
		Next
		KWArgs = ConvertedKWArgs
	End If
	Return Array(Args, KWArgs)
End Sub

Public Sub RunAsync(Target As PyObject, Method As String, Args As List, KWArgs As Map) As ResumableSub
	Dim res As PyObject = CreatePyObject(0)
	Dim aaa() As Object = ArrangeArgs(Args, KWArgs)
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN_ASYNC, Array(Target, Method, aaa(0), aaa(1), res))
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return res
End Sub

Public Sub Get(PyObjects As List) As ResumableSub
	Dim keys As List
	keys.Initialize
	For Each py As PyObject In PyObjects
		keys.Add(py.Key)
	Next
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_GET, keys)
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return TASK.Extra
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