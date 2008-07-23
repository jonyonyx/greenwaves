//import groovy.sql.Sql
//xlsfile = /C:\projects\62832\data\data.xls/
//mdbfile = /C:\projects\62832\test_scenarios\scenario_basis_dag\vissim.mdb/
//
//mdbcs = "jdbc:odbc:Driver={Microsoft Access Driver (*.xls)};DBQ=$mdbfile"
//xlscs = "jdbc:odbc:Driver={Microsoft Excel Driver (*.xls)};DBQ=$xlsfile"
//
//sql = Sql.newInstance(xlscs)
//
//sql.eachRow('SELECT DISTINCT(Intersection) as intersectionName FROM [counts$]',{
//  println it.intersectionName
//})

import org.codehaus.groovy.scriptom.*

def outlook = new ActiveXProxy("Outlook.Application");
def message = outlook.CreateItem(0);
def emails = "user1@domain1.com;user2@domain2.com";
def rec = message.Recipients.add(emails);
rec.Type = 1 // To = 1, CC = 2, BCC = 3
message.Display(true);
