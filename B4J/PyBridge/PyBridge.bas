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
	Type PyTask (TaskId As Int, TaskType As Int, Extra As List)
	Type InternalPyTaskAsyncResult (PyObject As PyObject, Value As Object, Error As Boolean)
	Type PyOptions (PythonExecutable As String, LocalPort As Int, _
		PyBridgePath As String, PyOutColor As Int, PyErrColor As Int, B4JColor As Int, _
		ForceCopyBridgeSrc As Boolean, WatchDogSeconds As Int, PyCacheFolder As String, EnvironmentVars As Map)
	Type InternalPyMethodArgs (Args As List, KWArgs As Map)
	Private comm As PyComm
	Private mCallback As Object
	Private mEventName As String
	
	Public Utils As PyUtils
	Public Builtins As PyWrapper
	Public Bridge As PyWrapper
	Public Sys As PyWrapper
	
	Private Shl As Shell
	Private mOptions As PyOptions
	Private Epsilon As Double = 0.0000001
	Private ShlReadLoopIndex As Int
	Public Const CALL_METHOD As String = "__call__"
End Sub

Public Sub Initialize (Callback As Object, EventName As String)
	mCallback = Callback
	mEventName = EventName
	mOptions.Initialize
	Utils.Initialize(Me, comm)
End Sub

'Starts the Python bridge server. Use Py.CreateOptions to create the Options object. 
Public Sub Start (Options As PyOptions)
	KillProcess
	mOptions = Options
	comm.Initialize(Me, Options.LocalPort)
	Utils.Comm = comm
	If Options.PythonExecutable <> "" Then
		If File.Exists(Options.PyBridgePath, "") = False Or mOptions.ForceCopyBridgeSrc Then
			File.Copy(File.DirAssets, "b4x_bridge.zip", Options.PyBridgePath, "")
			Utils.PyLog(Utils.B4JPrefix, mOptions.B4JColor, "Python package copied to: " & Options.PyBridgePath)
		End If
		If File.Exists(Options.PythonExecutable, "") = False Then
			LogError("Python executable not found!")
			comm.CloseServer
		End If
		Dim Shl As Shell
		Shl.Initialize("shl", Options.PythonExecutable, Array As String("-u", "-m", "b4x_bridge", comm.Port, mOptions.WatchDogSeconds))
		Options.EnvironmentVars.Put("PYTHONPATH", Options.PyBridgePath)
		If Options.PyCacheFolder <> "" Then Options.EnvironmentVars.Put("PYTHONPYCACHEPREFIX", Options.PyCacheFolder)
		Shl.SetEnvironmentVariables(Options.EnvironmentVars)
		Shl.Run(-1)
		ShlReadLoop
	End If
End Sub

Private Sub ShlReadLoop
	ShlReadLoopIndex = ShlReadLoopIndex + 1
	Dim MyIndex As Int = ShlReadLoopIndex
	Do While MyIndex = ShlReadLoopIndex And Initialized(Shl)
		HandleOutAndErr(Shl.GetTempOut2(True), Shl.GetTempErr2(True))
		Sleep(50)
	Loop
End Sub

Private Sub HandleOutAndErr (out As String, err As String)
	If out.Length > 0 Then Utils.PyLog(Utils.PyOutPrefix, mOptions.PyOutColor, out)
	If err.Length > 0 Then Utils.PyLog(Utils.PyErrPrefix, mOptions.PyErrColor, err)
End Sub



Private Sub shl_ProcessCompleted (Success As Boolean, ExitCode As Int, StdOut As String, StdErr As String)
	HandleOutAndErr(StdOut, StdErr)	
	Utils.PyLog(Utils.B4JPrefix, mOptions.B4JColor, $"Process completed. ExitCode: ${ExitCode}"$)
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
	opt.PyBridgePath = File.Combine(File.DirData("pybridge"), $"b4x_bridge_${Utils.PythonBridgeCodeVersion}.zip"$)
	opt.B4JColor = 0xFF727272
	opt.PyErrColor = 0xFFF74479
	opt.PyOutColor = 0xFF446EF7
	opt.WatchDogSeconds = 30
	opt.PyCacheFolder = File.DirData("pybridge")
	opt.EnvironmentVars =  CreateMap("PYTHONUTF8": 1)
	If Utils.DetectOS = "windows" Then opt.EnvironmentVars.Put("MPLCONFIGDIR", GetEnvironmentVariable("USERPROFILE", ""))
	Return opt
End Sub

Private Sub State_Changed (OldState As Int, NewState As Int)
	If NewState = comm.STATE_CONNECTED Then
		AfterConnection
	Else
		Utils.Disconnected
		KillProcess
	End If
	If NewState = comm.STATE_CONNECTED Or (OldState = comm.STATE_WAITING_FOR_CONNECTION And NewState = comm.STATE_DISCONNECTED) Then
		CallSubDelayed2(mCallback, mEventName & "_connected", NewState = comm.STATE_CONNECTED)
	Else if SubExists(mCallback, mEventName & "_disconnected") Then
		CallSubDelayed(mCallback, mEventName & "_disconnected")
	End If
End Sub

Private Sub AfterConnection
	Bridge.Initialize(Me, Utils.CreatePyObject(1))
	Builtins.Initialize(Me, Utils.CreatePyObject(3))
	Utils.Connected(Utils.CreatePyObject(2), mOptions)
	Sys = ImportModule("sys")
	RunNoArgsCode("import sys")
End Sub

'Flushes the output queue. Can be used with Wait For to wait for the Python process to complete executing the queue.
'<code>Wait For (py.Flush) Complete (Unused As Boolean)</code>
Public Sub Flush As ResumableSub
	Wait For (Utils.Flush) Complete (unused As Boolean)
	Return unused
End Sub

Private Sub Task_Received(TASK As PyTask)
	If TASK.TaskType = Utils.TASK_TYPE_PING Then
		comm.SendTask(Utils.CreatePyTask(0, Utils.TASK_TYPE_PING, Array()))
	Else If TASK.TaskType <> Utils.TASK_TYPE_EVENT Then
		LogError("Unexpected message: " & TASK)
	Else
		Dim EventName As String = TASK.Extra.Get(0)
		Dim Params As Map = TASK.Extra.Get(1)
		CallSubDelayed3(mCallback, mEventName & "_event", EventName, Params)
	End If
End Sub

'Kills the Python process and closes the connection.
Public Sub KillProcess
	Try
		ShlReadLoopIndex = ShlReadLoopIndex + 1
		If Initialized(comm) Then
			comm.CloseServer
		End If
		If mOptions.PythonExecutable <> "" And Initialized(Shl) Then
			Shl.KillProcess
		End If
	Catch
		Log(LastException)
	End Try
End Sub

'Remotely prints the values or PyWrappers. Separated by space.
Public Sub Print (Objects As List, StdErr As Boolean)
	Dim Code As String = $"
def _print(obj, StdErr):
	print(*obj, file=sys.stderr if StdErr else sys.stdout)
"$
	RunCode("_print", Array(Objects, StdErr), Code)
End Sub

Private Sub RegisterMember (KeyName As String, ClassCode As String, Overwrite As Boolean)
	If Utils.RegisteredMembers.Contains(KeyName) = False Or Overwrite Then
		Builtins.RunArgs("exec", Array(ClassCode, Utils.EvalGlobals, Null), Null)
		Utils.RegisteredMembers.Add(KeyName)
	End If
End Sub

'Runs a Python function or class. Note that the code is registered once and is then reused.
'It is recommended to use the "RunCode" code snippet that creates a sub that calls RunCode.
Public Sub RunCode (MemberName As String, Args As List, FunctionCode As String) As PyWrapper
	RegisterMember(MemberName, FunctionCode, False)
	Return GetMember(MemberName).RunArgs(CALL_METHOD, Args, Null)
End Sub

'Runs the provided Python code. It runs using the same global namespace as RunCode.
Public Sub RunNoArgsCode (Code As String)
	Builtins.RunArgs("exec", Array(Code, Utils.EvalGlobals, Null), Null)
End Sub

'Runs a single statement and returns the result (PyWrapper).
'Example: <code>Py.Utils.RunStatement("10 * 15").Print</code>
Public Sub RunStatement (Code As String) As PyWrapper
	Return RunStatement2(Code, Null)
End Sub
'Runs a single statement and returns the result (PyWrapper). Allows passing a map with a set of "local" variables.
'Example: <code>Py.Utils.RunStatement2($"locals()["x"] + 10"$, CreateMap("x": 20)).Print</code>
Public Sub RunStatement2 (Code As String, Locals As Map) As PyWrapper
	If NotInitialized(Locals) Then Locals = B4XCollections.GetEmptyMap
	Return Builtins.RunArgs ("eval", Array(Code, Utils.EvalGlobals, Locals), Null)
End Sub

'Returns a member or attribute that was previously added to the global namespace.
Public Sub GetMember(Member As String) As PyWrapper
	Return Utils.EvalGlobals.Run("__getitem__").Arg(Member)
End Sub

'Imports a module.
Public Sub ImportModule (Module As String) As PyWrapper
	Return Utils.ImportLib.Run("import_module").Arg(Module)
End Sub

'Creates a slice object from Start (inclusive) to Stop (exclusive). Pass Null to omit a value.
Public Sub Slice (StartValue As Object, StopValue As Object) As PyWrapper
	Return Slice2(StartValue, StopValue, Null)
End Sub

'Same as Slice with an additional step value. Note that the value can be negative to traverse the collection backward.
Public Sub Slice2 (StartValue As Object, StopValue As Object, StepValue As Object) As PyWrapper
	Return Builtins.RunArgs("slice", Array(ConvertToIntIfMatch(StartValue), ConvertToIntIfMatch(StopValue), ConvertToIntIfMatch(StepValue)), Null)
End Sub

'Utility to prevent ints being treated as floats.
Public Sub ConvertToIntIfMatch (o As Object) As Object
	If o Is Float Or o Is Double Then
		Dim d As Double = o
		Dim i As Int = d
		If Abs(d - i) < Epsilon Then Return i
	End If
	Return o
End Sub

'Fetches multiple objects and returns a list. Unserializable objects will be returned as a string.
'Example: <code>Wait For (Py.Utils.FetchObjects(Array(x, y)) Complete (Fetched As List)</code>
Public Sub FetchObjects (Objects As List) As ResumableSub
	Dim list As PyWrapper = WrapObject(Objects)
	Wait For (ConvertUnserializable(list).Fetch) Complete (Result As PyWrapper)
	Return Result.Value.As(List)
End Sub

Private Sub ConvertUnserializable (List As Object) As PyWrapper
	Dim Code As String = $"
def ConvertUnserializable (bridge, list1):
	print(type(bridge))
	l = map(lambda x: bridge.comm.serializator.is_serializable(x), list1)
	return [x if y is None else str(y)[:100] for x, y in zip(list1, l)]
"$
	Return RunCode("ConvertUnserializable", Array(Bridge, List), Code)
End Sub

Public Sub PyIIf (Condition As Object, TrueValue As Object, FalseValue As Object) As PyWrapper
	Return RunStatement2($"locals()["TrueValue"] if locals()["Condition"] else locals()["FalseValue"]"$, _
		CreateMap("TrueValue": TrueValue, "Condition": Condition, "FalseValue": FalseValue))
End Sub

'Sends the object to the Python process and returns a PyWrapper. The object must be serializeable with B4XSerializator.
Public Sub WrapObject (Obj As Object) As PyWrapper
	Dim Code As String = $"
def WrapObject(obj):
	return obj
"$
	Return RunCode("WrapObject", Array(Obj), Code)
End Sub



