Sub TrimSelection()
    For Each r In Selection
        r.Value = Trim(r.Value)
    Next
End Sub

