B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10
@EndOfDesignText@
Sub Class_Globals
	Public Wrapper As PyWrapper
End Sub

Public Sub Initialize (bridge As PyBridge, obj As PyObject)
	Wrapper.Initialize(bridge, obj)
End Sub

Public Sub ImportModule (Module As String) As PyWrapper
	Return Wrapper.Run("import_module", Array(Module))
End Sub