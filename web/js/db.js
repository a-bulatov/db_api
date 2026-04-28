const pstyle = 'border: 1px solid #efefef; padding: 5px';

new w2layout({
     box: '#layout',
     name: 'layout',
     panels: [
         { type: 'left', resizable: true, size: 200, style: pstyle },
         { type: 'main', resizable: true, style: pstyle,
            tabs: {
                 name: 'tabs',
                 active: 'info',
                 tabs: [
                     { id: 'info', text: 'Определение' },
                     { id: 'console', text: 'Консоль' },
                     { id: 'data', text: 'Данные' },
                 ],
                 onClick(event) {
                      let info = document.getElementById('infoEditor')
                      let cons = document.getElementById('consoleEditor')
                      let data = document.getElementById('dataGrid')
                      let run_btn = document.getElementById('btnRun')
                      info.style.display = 'none'
                      cons.style.display = 'none'
                      data.style.display = 'none'
                      run_btn.disabled = event.target == "data"
                      w2ui.layout.hide('preview');
                      switch(event.target){
                        case("info"):
                           info.style.display = 'block'
                           window.info_editor.refresh()
                           break
                        case("console"):
                           cons.style.display = 'block'
                           window.console_editor.refresh()
                           break
                        case("data"):
                           data.style.display = 'block'
                           w2ui.grid.render('#dataGrid')
                           break
                      }
                 }
            },
            html: `
                <div id="infoEditor" style="full"></div>
                <div id="consoleEditor" style="full" hidden></div>
                <div id="dataGrid" style="width: 100%, ;height: 100%; background-color: #f0f0f0" hidden></div>`
         },
         { type: 'preview', size: '50%', resizable: true, hidden: true, style: pstyle, html: `
            <div id="previewError" style="full" hidden></div>
            <div id="previewData" class="tabs" hidden>
              <div id="previewToolbar"></div>
              <div class="full" hidden id="previewNotify">Контент 1</div>
              <div class="full" hidden id="previewTable">Контент 2</div>
            </div>
            </div>
         ` },
     ]
 })

new w2toolbar({
    box: '#previewToolbar',
    name: 'previewToolbar',
    items: [
        { type: 'radio', id: 'notify', group: '1', text: 'Результат', icon: 'w2ui-icon-info', checked: true },
        { type: 'radio', id: 'data', group: '1', text: 'Данные', icon: 'fa fa-table' },
        { type: 'break' },
        { type: 'spacer' },
        { type: 'button', id: 'item6', text: 'Выгрузить', icon: 'w2ui-icon-paste' }
    ],
    onClick(event) {
        let notify = document.getElementById('previewNotify')
        let table = document.getElementById('previewTable')
        switch(event.target) {
            case ('notify') :
                table.style.display = 'none'
                notify.style.display = 'block'
                break
            case ('data') :
                table.style.display = 'block'
                notify.style.display = 'none'
                break
        }
    }
})


new w2sidebar({
    topHTML: `<div style="background-color: #eee; padding: 10px 5px; border-bottom: 1px solid silver">
    <button class="w2ui-btn action" onclick="refreshClick()">
     <i class="fas fa-refresh"></i>
    </button>
    <button class="w2ui-btn action"  onclick="runClick()" id="btnRun">
     <i class="fas fa-play"></i>
    </button>
    </div>`,
    name: 'sidebar',
    nodes: [],
    onClick: function (event) {
         getNodeInfo(event.target)
    },
})

w2ui.layout.html('left', w2ui.sidebar)


new w2grid({
  name: 'grid',
  show: {
      toolbar: true,
      toolbarDelete: true
  },
  columns: [
      { field: 'fname', text: 'First Name', size: '33%', sortable: true, searchable: true },
      { field: 'lname', text: 'Last Name', size: '33%', sortable: true, searchable: true },
      { field: 'email', text: 'Email', size: '33%' },
      { field: 'sdate', text: 'Start Date', size: '120px', render: 'date' }
  ],
  records: [
      { recid: 1, fname: 'John', lname: 'Doe', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 2, fname: 'Stuart', lname: 'Motzart', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 3, fname: 'Jin', lname: 'Franson', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 4, fname: 'Susan', lname: 'Ottie', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 5, fname: 'Kelly', lname: 'Silver', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 6, fname: 'Francis', lname: 'Gatos', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 7, fname: 'Mark', lname: 'Welldo', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 8, fname: 'Thomas', lname: 'Bahh', email: 'jdoe@gmail.com', sdate: '4/3/2012' },
      { recid: 9, fname: 'Sergei', lname: 'Rachmaninov', email: 'jdoe@gmail.com', sdate: '4/3/2012' }
  ]})



function refreshMeta(){
    fetch('/db', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "db", "params":{"do": "get_db_objects"}})
    }).then(response => response.json())
    .then(result => {
          let sel = null;
          let sidebar= w2ui.sidebar
          if (sidebar.nodes.length > 0) sel=sidebar.selected[0]
          let nodeIds = sidebar.nodes.map(n => n.id)
          sidebar.remove.apply(sidebar, nodeIds)
          result.result.forEach((item)=>{
            sidebar.add(item)
          })
          if (sel === null) sel = result.result[0]["id"]
          sidebar.refresh()
          sidebar.click(sel)
    })
    .catch(error => console.error('Error:', error));
}

function getNodeInfo(id){
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "get_info", "id": id}})
    }).then(response => response.json())
    .then(result => {
            window.info_editor.setValue(result.result)
    })
    .catch(error => console.error('Error:', error))
}

window.onload = function() {
   window.info_editor = CodeMirror(document.getElementById('infoEditor'), {
     lineNumbers: true,
     tabSize: 4,
     value: '',
     mode: 'sql',
     theme: 'idea',
     matchBrackets:true
   })
   window.console_editor = CodeMirror(document.getElementById('consoleEditor'), {
     lineNumbers: true,
     tabSize: 4,
     value: '',
     mode: 'sql',
     theme: 'idea',
     matchBrackets:true
   });

   refreshMeta();
};

function refreshClick(){
    refreshMeta()
}

function runClick(){
    let editor = w2ui.layout.get("main").tabs.active == "console" ? window.console_editor  : window.info_editor
    let sql_text = editor.getSelection()
    if(sql_text == "") sql_text = editor.getValue()
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "sql", "sql": btoa(sql_text)}})
    }).then(response => response.json())
    .then(result => {
        let data = document.getElementById('previewData')
        let error = document.getElementById('previewError')
        let notify = document.getElementById('previewNotify')
        let table = document.getElementById('previewTable')
        error.style.display = 'none'
        data.style.display = 'block'
        table.style.display = 'none'
        notify.style.display = 'block'
        console.log(result.result)
        w2ui.layout.show('preview');
    })
    .catch(error => console.error('Error:', error))
}