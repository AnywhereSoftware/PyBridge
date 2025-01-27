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

Public Sub ImportModule (Module As String) As PyWrapper
	Return wrapper.Run("import_module", Array(Module))
End Sub