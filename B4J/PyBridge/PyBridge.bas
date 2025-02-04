B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#Event: Connected (Success As Boolean)
#Event: Disconnected
#Event: Event (Name As String, Params As Map)
Sub Class_Globals
	Type PyObject (Key As Int)
	Private TASK_TYPE_RUN = 1, TASK_TYPE_GET = 2, TASK_TYPE_RUN_ASYNC = 3, TASK_TYPE_CLEAN = 4 _
		, TASK_TYPE_ERROR = 5, TASK_TYPE_EVENT = 6, TASK_TYPE_PING = 7, TASK_TYPE_FLUSH = 8 As Int
	Type PyTask (TaskId As Int, TaskType As Int, Extra As List)
	Type InternalPyTaskAsyncResult (PyObject As PyObject, Value As Object, Error As Boolean)
	Type PyOptions (PythonExecutable As String, LocalPort As Int, _
		PyBridgePath As String, PyOutColor As Int, PyErrColor As Int, B4JColor As Int, _
		ForceCopyBridgeSrc As Boolean, WatchDogSeconds As Int)
	Private cleaner As JavaObject
	Private comm As PyComm
	Private mCallback As Object
	Private mEventName As String
	Private CleanerClass As String
	Public Utils As PyUtils
	Private TaskIdCounter, PyObjectCounter As Int
	Private EmptyList As List, EmptyMap As Map
	Public Bridge As PyWrapper
	Private CleanerIndex As Int
	Private Shl As Shell
	Public mOptions As PyOptions
	Public PythonBridgeCodeVersion As String = "0.11"
	Public PyOutPrefix = "(pyout)", PyErrPrefix = "(pyerr)", B4JPrefix = "(b4j)" As String
End Sub

Public Sub Initialize (Callback As Object, EventName As String)
	cleaner = cleaner.InitializeStatic("java.lang.ref.Cleaner").RunMethod("create", Null)
	mCallback = Callback
	mEventName = EventName
	EmptyList.Initialize
	EmptyMap.Initialize
	CleanerClass = GetType(Me) & "$CleanRunnable"
	mOptions.Initialize
	
End Sub

'Starts the Python bridge server. Use Py.CreateOptions to create the Options object. 
Public Sub Start (Options As PyOptions)
	KillProcess
	mOptions = Options
	comm.Initialize(Me, Options.LocalPort)
	PyObjectCounter = 100
	If Options.PythonExecutable <> "" Then
		If File.Exists(Options.PyBridgePath, "") = False Or mOptions.ForceCopyBridgeSrc Then
			File.Copy(File.DirAssets, "b4x_bridge.zip", Options.PyBridgePath, "")
			PyLog(B4JPrefix, mOptions.B4JColor, "Python package copied to: " & Options.PyBridgePath)
		End If
		Dim Shl As Shell
		Shl.Initialize("shl", Options.PythonExecutable, Array As String("-u", "-m", "b4x_bridge", comm.Port, mOptions.WatchDogSeconds))
		Shl.SetEnvironmentVariables(CreateMap("PYTHONPATH": Options.PyBridgePath, _
			"PYTHONUTF8": 1))
		Shl.RunWithOutputEvents(-1)
	End If
	
End Sub

Private Sub Shl_StdOut (Buffer() As Byte, Length As Int)
	PyLog(PyOutPrefix, mOptions.PyOutColor, BytesToString(Buffer, 0, Length, "utf8"))
End Sub

Private Sub Shl_StdErr (Buffer() As Byte, Length As Int)
	PyLog(PyErrPrefix, mOptions.PyErrColor, BytesToString(Buffer, 0, Length, "utf8"))
End Sub

Private Sub shl_ProcessCompleted (Success As Boolean, ExitCode As Int, StdOut As String, StdErr As String)
	PyLog(B4JPrefix, mOptions.B4JColor, $"Process completed. ExitCode: ${ExitCode}"$)
	Dim Shl As Shell
	comm.CloseServer
End Sub

'Bridge options.
'PythonExecutable - Path to the python executable file.
'PyBridgePath (optional) - Folder where the Python client program will be stored. File.DirData("pybridge") by default.
'Other settings include the log colors and the internal watchdog timeout.
Public Sub CreateOptions (PythonExecutable As String) As PyOptions
	Dim opt As PyOptions
	opt.Initialize
	opt.PythonExecutable = PythonExecutable
	opt.PyBridgePath = File.Combine(File.DirData("pybridge"), $"b4x_bridge_${PythonBridgeCodeVersion}.zip"$)
	opt.B4JColor = 0xFF727272
	opt.PyErrColor = 0xFFF74479
	opt.PyOutColor = 0xFF446EF7
	opt.WatchDogSeconds = 30
	Return opt
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

Private Sub State_Changed (OldState As Int, NewState As Int)
	If NewState = comm.STATE_CONNECTED Then
		Bridge.Initialize(Me, CreatePyObject(1))
		Utils.Initialize(Me, CreatePyObject(3), CreatePyObject(2))
		CheckKeysNeedToBeCleaned
		If Shl.IsInitialized Then
			Me.as(JavaObject).RunMethod("add_shutdown_hook", Array(Shl))
		End If
	Else
		CleanerIndex = CleanerIndex + 1
		KillProcess
	End If
	If NewState = comm.STATE_CONNECTED Or (OldState = comm.STATE_WAITING_FOR_CONNECTION And NewState = comm.STATE_DISCONNECTED) Then
		CallSubDelayed2(mCallback, mEventName & "_connected", NewState = comm.STATE_CONNECTED)
	Else if SubExists(mCallback, mEventName & "_disconnected") Then
		CallSubDelayed(mCallback, mEventName & "_disconnected")
	End If
End Sub

'Kills the Python process.
Public Sub KillProcess
	Try
		If mOptions.PythonExecutable <> "" And Shl.IsInitialized Then Shl.KillProcess
	Catch
		Log(LastException)
	End Try
End Sub

Private Sub Task_Received(TASK As PyTask)
	If TASK.TaskType = TASK_TYPE_PING Then
		comm.SendTask(CreatePyTask(0, TASK_TYPE_PING, Array()))
	Else If TASK.TaskType <> TASK_TYPE_EVENT Then
		LogError("Unexpected message: " & TASK)
	Else
		Dim EventName As String = TASK.Extra.Get(0)
		Dim Params As Map = TASK.Extra.Get(1)
		CallSubDelayed3(mCallback, mEventName & "_event", EventName, Params)
	End If
End Sub

'Use PyWrapper.Run instead.
Public Sub Run (Target As PyObject, Method As String, Args As List, KWArgs As Map) As PyObject
	Dim res As PyObject = CreatePyObject(0)
	If Args = Null Or Args.IsInitialized = False Then Args = EmptyList
	If KWArgs = Null Or KWArgs.IsInitialized = False Then KWArgs = EmptyMap
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN, _
		Array(Target.Key, Method, Args, KWArgs, res.Key))
	comm.SendTask(TASK)
	Return res
End Sub

'Flushes the output queue. Can be used with Wait For to wait for the Python process to complete executing the queue.
'<code>Wait For (py.Flush) Complete (Unused As Boolean)</code>
Public Sub Flush As ResumableSub
	Dim task As PyTask = CreatePyTask(0, TASK_TYPE_FLUSH, Array())
	comm.SendTaskAndWait(task)
	Wait For (task) AsyncTask_Received (task As PyTask)
	Return True
End Sub

'Use PyWrapper.RunAsync instead.
Public Sub RunAsync(Target As PyObject, Method As String, Args As List, KWArgs As Map) As ResumableSub
	Dim res As PyObject = CreatePyObject(0)
	If Args = Null Or Args.IsInitialized = False Then Args = EmptyList
	If KWArgs = Null Or KWArgs.IsInitialized = False Then KWArgs = EmptyMap
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_RUN_ASYNC, Array(Target.Key, Method, Args, KWArgs, res.Key))
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, res)
End Sub

Private Sub CheckForErrorsAndReturn (TASK As PyTask, PyObject As PyObject) As InternalPyTaskAsyncResult
	If TASK.TaskType = TASK_TYPE_ERROR Then
		PyLog(B4JPrefix, mOptions.PyErrColor, TASK.Extra.Get(0))
	End If
	Return CreateInternalPyTaskAsyncResult(PyObject, TASK.Extra.Get(0), TASK.TaskType == TASK_TYPE_ERROR)
End Sub

'Use PyWrapper.Fetch instead.
Public Sub Fetch(PyObject As PyObject) As ResumableSub
	Dim TASK As PyTask = CreatePyTask(0, TASK_TYPE_GET, Array(PyObject.Key))
	comm.SendTaskAndWait(TASK)
	Wait For (TASK) AsyncTask_Received (TASK As PyTask)
	Return CheckForErrorsAndReturn(TASK, PyObject)
End Sub

'Used internally. Note that it expects a sub in the Main module with the following code:
'<code>Public Sub PyLogHelper (Text As String, Clr As Int)
' LogColor (Text, Clr)
'End Sub</code>
Public Sub PyLog(Prefix As String, Clr As Int, O As Object)
	#if not(DISABLE_PYBRIDGE_LOGS)
	If o Is PyWrapper Then
		Utils.Print(o)
	Else
		Dim s As String = o
		s = s.Trim
		If s.Length = 0 Then Return
		If Clr <> 0 Then
			Main.PyLogHelper(Prefix & " " & s, Clr)
		Else
			Log(Prefix & " " & s.Trim)
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

Private Sub RegisterForCleaning (Py As PyObject)
	Dim Runnable As JavaObject
	Runnable.InitializeNewInstance(CleanerClass, Array(Py.Key))
	cleaner.RunMethod("register", Array(Py, Runnable))
End Sub

Private Sub CheckKeysNeedToBeCleaned
	CleanerIndex = CleanerIndex + 1
	Dim MyIndex As Int = CleanerIndex
	Do While MyIndex = CleanerIndex
		Sleep(1000)
		Dim c As JavaObject
		Dim keys As List = c.InitializeStatic(CleanerClass).RunMethod("getKeys", Null)
		If keys.Size > 0 Then
			comm.SendTask(CreatePyTask(0, TASK_TYPE_CLEAN, keys))
		End If
	Loop
End Sub


#if Java

public void add_shutdown_hook(final anywheresoftware.b4j.objects.Shell shl) {
	Runtime.getRuntime().addShutdownHook(new Thread(() -> {
			try {
				if (shl.IsInitialized())
					shl.KillProcess();
			} catch (Exception e) {
				e.printStackTrace();
			}
        }));
}

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