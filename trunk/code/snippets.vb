Sub FormatSheet(sheetname)
    
    Dim ds As Worksheet
    Set ds = Sheets(sheetname)
    
    Dim headers As Range, header As Range
    Set headers = Range(ds.Range("a1"), ds.Range("a1").End(xlToRight))
    
    For Each header In headers
        coltitle = header.Value
        
        If coltitle = "Klokkeslæt" Then
            With Range(header.Offset(1), header.End(xlDown))
                .NumberFormat = "hh:mm:ss"
                ' trim klokkeslæt values if needed
                
                For Each r In .Cells
                    oldval = r.Value
                    If oldval Like " *" Then
                        r.Value = Trim(oldval)
                    End If
                Next
            End With
        End If
    Next
    
    ' toggle autofilter
    If ds.AutoFilterMode Then
        headers.AutoFilter
    End If
    headers.AutoFilter
    
    headers.Font.Bold = True
    
    ds.Columns.AutoFit
    ds.Activate
    ds.Range("a1").Select
End Sub
Sub ApplyFormatting()
    For Each ds In ActiveWorkbook.Sheets
        FormatSheet ds.Name
    Next
End Sub
