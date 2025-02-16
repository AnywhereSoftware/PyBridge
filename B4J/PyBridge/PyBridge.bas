B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#Event: Connected (Success As Boolean)
#Event: Disconnected
#Event: Event (Args As Map)
Sub Class_Globals
	Type PyObject (Key As Int)
	Type PyTask (TaskId As Int, TaskType As Int, Extra As List)
	Type InternalPyTaskAsyncResult (PyObject As PyObject, Value As Object, Error As Boolean)
	Type PyOptions (PythonExecutable As String, LocalPort As Int, _
		PyBridgePath As String, PyOutColor As Int, PyErrColor As Int, B4JColor As Int, _
		ForceCopyBridgeSrc As Boolean, WatchDogSeconds As Int, PyCacheFolder As String, EnvironmentVars As Map, _
		TrackLineNumbers As Boolean)
	Type InternalPyMethodArgs (Args As List, KWArgs As Map, Task As PyTask)
	Private comm As PyComm
	Private mCallback As Object
	Private mEventName As String
	Public Utils As PyUtils
	Public Builtins As PyWrapper
	Public Bridge As PyWrapper
	Public Itertools As PyWrapper
	Public Sys As PyWrapper
	Private Shl As Shell
	Private mOptions As PyOptions
	Private ShlReadLoopIndex As Int
	Public ErrorHandler As PyErrorHandler
	Public PyLastException As String
End Sub

'Initializes the bridge.
Public Sub Initialize (Callback As Object, EventName As String)
	mCallback = Callback
	mEventName = EventName
	mOptions.Initialize
	ErrorHandler.Initialize(Utils)
	Utils.Initialize(Me, comm)
End Sub

'Starts the Python bridge server. Use Py.CreateOptions to create the Options object. 
'Wait For the Connected event after this call.
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

Private Sub HandleOutAndErr (out As String, Err As String)
	If out.Length > 0 Then Utils.PyLog(Utils.PyOutPrefix, mOptions.PyOutColor, out)
	If Err.Length > 0 Then Utils.PyLog(Utils.PyErrPrefix, mOptions.PyErrColor, Err)
End Sub



Private Sub shl_ProcessCompleted (Success As Boolean, ExitCode As Int, StdOut As String, StdErr As String)
	HandleOutAndErr(StdOut, StdErr)	
	Utils.PyLog(Utils.B4JPrefix, mOptions.B4JColor, $"Process completed. ExitCode: ${ExitCode}"$)
	Dim Shl As Shell
	comm.CloseServer
End Sub

'Bridge options. All fields are optional except of PythonExecutable.
'PythonExecutable - Path to the python executable file.
'PyBridgePath - Folder where the Python client program will be stored. File.DirData("pybridge") by default.
'PyCacheFolder - Folder where the cached compiled scripts will be stored. File.DirData("pybridge") by default.
'EnvironmentVars - Environment variables of the Python process.
'TrackLineNumbers - Whether B4X line information is tracked. Line information is added to error messages. 
'This is True by default. Note that it adds an overhead to the method calls (not to the actual runtime of the Python process).
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
	opt.TrackLineNumbers = True
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
	Itertools = ImportModule("itertools")
End Sub

'Flushes the output queue. Can be used with Wait For to wait for the Python process to complete executing the queue.
'If an exception was raised during execution then Success will be False and the error message will be avilable with py.PyLastException.
'<code>Wait For (py.Flush) Complete (Success As Boolean)</code>
Public Sub Flush As ResumableSub
	Wait For (Utils.Flush) Complete (Success As Boolean)
	Return Success
End Sub

Private Sub Task_Received(TASK As PyTask)
	If TASK.TaskType = Utils.TASK_TYPE_PING Then
		comm.SendTask(Utils.CreatePyTask(0, Utils.TASK_TYPE_PING, Array()))
	Else If TASK.TaskType <> Utils.TASK_TYPE_EVENT Then
		LogError("Unexpected message: " & TASK)
	Else
		Dim EventName As String = TASK.Extra.Get(0)
		Dim Params As Map = TASK.Extra.Get(1)
		CallSubDelayed2(mCallback, mEventName & "_" & EventName, Params)
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

'Remotely prints the object.
Public Sub Print(Obj As Object)
	PrintJoin(Array(Obj), False)
End Sub

'Remotely prints the objects. Separated by space.
Public Sub PrintJoin (Objects As List, StdErr As Boolean)
	Dim Code As String = $"
def _print(obj, StdErr):
	print(*obj, file=sys.stderr if StdErr else sys.stdout)
"$
	RunCode("_print", Array(Objects, StdErr), Code)
End Sub


Private Sub RegisterMember (KeyName As String, ClassCode As String, Overwrite As Boolean)
	If Utils.RegisteredMembers.Contains(KeyName) = False Or Overwrite Then
		RunNoArgsCode(ClassCode)
		Utils.RegisteredMembers.Add(KeyName)
	End If
End Sub

'Runs a Python function or class. Note that the code is registered once and is then reused.
'It is recommended to use the "RunCode" code snippet that creates a sub that calls RunCode.
Public Sub RunCode (MemberName As String, Args As List, FunctionCode As String) As PyWrapper
	RegisterMember(MemberName, FunctionCode, False)
	Return GetMember(MemberName).Call.Args(Args)
End Sub

'Runs the provided Python code. It runs using the same global namespace as RunCode.
Public Sub RunNoArgsCode (Code As String)
	Builtins.RunArgs("exec", Array(Code, Utils.EvalGlobals, Null), Null)
End Sub

'Runs a single statement and returns the result as a PyWrapper.
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
	Return Utils.EvalGlobals.Get(Member)
End Sub

'Imports a module.
Public Sub ImportModule (Module As String) As PyWrapper
	RunNoArgsCode("import " & Module)
	Return Utils.ImportLib.Run("import_module").Arg(Module)
End Sub

'Similar to calling import X from y.
Public Sub ImportModuleFrom(FromModule As String, ImportMember As String) As PyWrapper
	Return ImportModule(FromModule).GetField(ImportMember)
End Sub

'Creates a slice object from Start (inclusive) to Stop (exclusive). Pass Null to omit a value.
Public Sub Slice (StartValue As Object, StopValue As Object) As PyWrapper
	Return Builtins.RunArgs("slice", Array(Utils.ConvertToIntIfMatch(StartValue), Utils.ConvertToIntIfMatch(StopValue)), Null)
End Sub

'Same as Slice(Null, Null). Equivalent to [:].
Public Sub SliceAll As PyWrapper
	Return Slice(Null, Null)
End Sub

'Casts the object to Python int.
Public Sub AsInt (o As Object) As PyWrapper
	Return Builtins.Run("int").Arg(o)
End Sub

'Casts the object to Python str (string).
Public Sub AsStr (o As Object) As PyWrapper
	Return Builtins.Run("str").Arg(o)
End Sub

'Casts the object to Python float.
Public Sub AsFloat (o As Object) As PyWrapper
	Return Builtins.Run("float").Arg(o)
End Sub

'Python Map method - executes the function on each item in the collection. Function will usually be created with Py.Lambda.
'<code>Dim Numbers As PyWrapper = Py.WrapObject(Array(0, 1, 2, 3, 4, 5, 6, 7, 8, 9))
'Numbers = Py.Map_(Py.Lambda("x: 2 * x"), Numbers).ToList
'Numbers.Print
'Numbers = Py.Filter(Py.Lambda("x: x < 10"), Numbers).ToList
'Numbers.Print2("even numbers smaller than 10:", "", False)</code>
Public Sub Map_(Function As Object, Iterable As Object) As PyWrapper
	Return Builtins.Run("map").Arg(Utils.ConvertLambdaIfMatch(Function)).Arg(Iterable)
End Sub

'Python filter method - filters the items based on the predicate. The predicate will usually be created with Py.Lambda.
'<code>Dim Numbers As PyWrapper = Py.WrapObject(Array(0, 1, 2, 3, 4, 5, 6, 7, 8, 9))
'Numbers = Py.Map_(Py.Lambda("x: 2 * x"), Numbers).ToList
'Numbers.Print
'Numbers = Py.Filter(Py.Lambda("x: x < 10"), Numbers).ToList
'Numbers.Print2("even numbers smaller than 10:", "", False)</code>
Public Sub Filter (Predicate As Object, Iterable As Object) As PyWrapper
	Return Builtins.Run("filter").Arg(Utils.ConvertLambdaIfMatch(Predicate)).Arg(Iterable)
End Sub

'Creates a lambda function. This is equivalent to calling RunStatement("lambda " & Code).
'<code>'<code>Dim Numbers As PyWrapper = Py.WrapObject(Array(0, 1, 2, 3, 4, 5, 6, 7, 8, 9))
'Numbers = Py.Map_(Py.Lambda("x: 2 * x"), Numbers).ToList
'Numbers.Print
'Numbers = Py.Filter(Py.Lambda("x: x < 10"), Numbers).ToList
'Numbers.Print2("even numbers smaller than 10:", "", False)</code></code>
Public Sub Lambda(Code As String) As PyWrapper
	Return RunStatement("lambda " & Code)
End Sub

'Process the next item of the iterator.
'<code>Dim Numbers As PyWrapper = Py.Range(20)
'Dim iter As PyWrapper = Numbers.Iter
'Do While True
'	Wait For (Py.PyNext(iter).Fetch) Complete (Result As PyWrapper)
'	If Result.IsSuccess = False Then Exit
'	Log(Result.Value)
'Loop</code>
Public Sub PyNext(Iter As PyWrapper) As PyWrapper
	Return Builtins.Run("next").Arg(Iter)
End Sub

'Fetches multiple objects and returns a list. Unserializable objects will be returned as a string.
'Example: <code>Wait For (Py.Utils.FetchObjects(Array(x, y)) Complete (Fetched As List)</code>
Public Sub FetchObjects (Objects As Object) As ResumableSub
	Dim List As PyWrapper = IIf(Objects Is PyWrapper, Objects, WrapObject(Objects))
	Wait For (ConvertUnserializable(List).Fetch) Complete (Result As PyWrapper)
	Return Result.Value.As(List)
End Sub

'Python range method.
Public Sub Range (FirstParam As Object) As PyWrapper
	Return Builtins.Run("range").Arg(FirstParam)
End Sub

Private Sub ConvertUnserializable (List As Object) As PyWrapper
	Dim Code As String = $"
def ConvertUnserializable (bridge, list1):
	l = map(lambda x: bridge.comm.serializator.is_serializable(x), list1)
	return [x if y is None else str(y)[:100] for x, y in zip(list1, l)]
"$
	Return RunCode("ConvertUnserializable", Array(Bridge, List), Code)
End Sub

'Similar to IIF. Note that both values will be evaluated.
Public Sub PyIIf (Condition As Object, TrueValue As Object, FalseValue As Object) As PyWrapper
	Return RunCode("PyIIF", Array(Condition, TrueValue, FalseValue), $"
def PyIIF(condition, TrueValue, FalseValue):
	res = TrueValue if condition else FalseValue
	if callable(res):
		return res()
	else:
		return res
"$)
End Sub

'Sends the object to the Python process and returns a PyWrapper. The object must be serializeable with B4XSerializator.
Public Sub WrapObject (Obj As Object) As PyWrapper
	Dim Code As String = $"
def WrapObject(obj):
	return obj
"$
	Return RunCode("WrapObject", Array(Obj), Code)
End Sub

'Python open method. Returns a file object. Call File.Run("close") to close it.
Public Sub Open (FilePath As Object, Mode As Object) As PyWrapper
	Return Builtins.Run("open").Arg(FilePath).Arg(Mode)
End Sub

#if UI
'Utility to convert an array of bytes to image.
Public Sub ImageFromBytes(Bytes() As Byte) As B4XBitmap
	Dim Image As Image
	Dim in As InputStream
	in.InitializeFromBytesArray(Bytes, 0, Bytes.Length)
	Image.Initialize2(in)
	in.Close
	Return Image
End Sub

'Utility to convert an image to an array of bytes.
Public Sub ImageToBytes (Image As B4XBitmap) As Byte()
	Dim out As OutputStream
	out.InitializeToBytesArray(0)
	Image.WriteToStream(out, 100, "PNG")
	Return out.ToBytesArray
End Sub
#End If

