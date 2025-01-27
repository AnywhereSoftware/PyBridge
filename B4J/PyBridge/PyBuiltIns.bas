B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public wrapper As PyWrapper
End Sub

Public Sub Initialize (bridge As PyBridge, obj As PyObject)
	wrapper.Initialize(bridge, obj)
End Sub

Public Sub Print (Obj As Object)
	wrapper.Run("print", Array(Obj))
End Sub