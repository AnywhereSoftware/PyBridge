B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
#ModuleVisibility: B4XLib
Sub Class_Globals
	Private srvr As ServerSocket
	Public const STATE_DISCONNECTED = 1, STATE_CONNECTED = 2 As Int
	Public State As Int = STATE_DISCONNECTED
	Public Port As Int
	Private mBridge As PyBridge
	Private astream As AsyncStreams
	Private ser As B4XSerializator
	Private WaitingTasks As Map
	Private jME As JavaObject
	Private FlatTasks As List
End Sub

Public Sub Initialize (Bridge As PyBridge, LocalPort As Int)
	InitializeWithLoopback(srvr, "srvr", LocalPort)
	Dim jo As JavaObject
	Dim correctClassesNames As Map = jo.InitializeStatic("anywheresoftware.b4a.randomaccessfile.RandomAccessFile").GetField("correctedClasses")
	correctClassesNames.Put("_pyobject", GetType(Bridge) & "$_pyobject")
	jME = Me
	WaitingTasks.Initialize
	Port = srvr.As(JavaObject).GetFieldJO("ssocket").RunMethod("getLocalPort", Null)
	mBridge = Bridge
	mBridge.PyLog(mBridge.B4JPrefix, mBridge.mOptions.B4JColor, "Server is listening on port: " & Port)
	srvr.Listen
	FlatTasks.Initialize
End Sub

Private Sub InitializeWithLoopback(Server As ServerSocket, EventName As String, vPort As Int)
	Server.Initialize(-1, EventName)
	Dim ia As JavaObject
	ia = ia.InitializeStatic("java.net.InetAddress").RunMethod("getLoopbackAddress", Null)
	Dim s As JavaObject = Server
	Dim socket As JavaObject
	socket.InitializeNewInstance("java.net.ServerSocket", Array(vPort, 50, ia))
	s.SetField("ssocket", socket)
End Sub

Private Sub Srvr_NewConnection (Successful As Boolean, NewSocket As Socket)
	If Successful Then
		mBridge.PyLog(mBridge.B4JPrefix, mBridge.mOptions.B4JColor, "connected")
'		astream.OutputQueueMaxSize = 1000000
		astream.InitializePrefix(NewSocket.InputStream, True, NewSocket.OutputStream, "astream")
		State = STATE_CONNECTED
		Sleep(100)
		StateChanged
	End If
End Sub

Private Sub AStream_NewData (Buffer() As Byte)
	Dim o() As Object = ser.ConvertBytesToObject(Buffer)
	Dim Task As PyTask = mBridge.CreatePyTask(o(0), o(1), o(2))
	If WaitingTasks.ContainsKey(Task.TaskId) Then
		jME.RunMethod("raiseEventWithSenderFilter", Array(mBridge, "asynctask_received", WaitingTasks.Remove(Task.TaskId), Array(Task)))
	Else
		CallSub2(mBridge, "Task_Received", Task)	
	End If
End Sub

Public Sub SendTask (Task As PyTask)
	If FlatTasks.Size = 0 Then CallSubDelayed(Me, "Flush")
	FlatTasks.AddAll(Array(Task.TaskId, Task.TaskType, Task.Extra))
End Sub

Public Sub Flush
	If FlatTasks.Size > 0 Then
		Dim res As Boolean = astream.Write(ser.ConvertObjectToBytes(FlatTasks))
		If astream.OutputQueueSize > 100 Then
			mBridge.PyLog(mBridge.B4JPrefix, mBridge.mOptions.B4JColor, "Output queue size: " & astream.OutputQueueSize)
		End If
		If res = False And astream.OutputQueueSize > 0 Then
			LogError("Queue is full!")
		End If
		FlatTasks.Clear
	End If
End Sub

Public Sub SendTaskAndWait (Task As PyTask)
	WaitingTasks.Put(Task.TaskId, Task)
	SendTask(Task)
	Flush
End Sub

Private Sub AStream_Error
	AStream_Terminated
End Sub

Private Sub AStream_Terminated
	State = STATE_DISCONNECTED
	FlatTasks.Clear
	srvr.Close
	If astream.IsInitialized Then astream.Close
	StateChanged
	mBridge.PyLog(mBridge.B4JPrefix, mBridge.mOptions.B4JColor, "disconnected")
End Sub

Private Sub StateChanged
	CallSub2(mBridge, "state_changed", State)
End Sub


#if Java
public void raiseEventWithSenderFilter(B4AClass target, String eventName, Object senderFilter, Object[] params) {
	target.getBA().raiseEventFromUI(senderFilter, eventName, params);
}
#End If