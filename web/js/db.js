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
                     { id: 'data', text: 'Данные' },
                     { id: 'console', text: 'Консоль' },
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
                      w2ui.layout.hide('preview')
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
                           refreshData()
                           break
                      }
                 }
            },
            html: `
                <div id="infoEditor" class="full"></div>
                <div id="consoleEditor" class="full" hidden></div>
                <div id="dataGrid" class="full" hidden></div>`
         },
         { type: 'preview', size: '50%', resizable: true, hidden: true, style: pstyle, html: `
            <div id="previewError" style="full" hidden></div>
            <div id="previewData" class="tabs" hidden>
              <div id="previewToolbar"></div>
              <div class="full" hidden id="previewNotify"><pre id="previewNotifyText"></pre></div>
              <div class="full" hidden id="previewTable"></div>
            </div>
            </div>
         ` },
     ],
     onResizing: function(event) {
         let table = document.getElementById('previewTable')
         let pv = w2ui.layout.get('preview')
         table.style.height=(pv.height - 50).toString() + "px"
     }
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
                notify.style.display = 'none'
                table.style.display = 'block'
                let pv = w2ui.layout.get('preview')
                table.style.height=(pv.height - 50).toString() + "px"
                break
        }
    }
})

new w2grid({
   name: 'result_grid',
   box:'#previewTable',
   columns: [
   ],
   records: [
   ]})

new w2grid({
  name: 'data_grid',
  box:"#dataGrid",
  columns: [
  ],
  records: [
  ]})


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
         let main = w2ui.layout.get('main')
         if(main.tabs.active != "console") w2ui.layout.hide('preview')
         getNodeInfo(event.target)
         if(main.tabs.active == "data") refreshData(event.target)
    },
})

w2ui.layout.html('left', w2ui.sidebar)

function refreshData(id=0){
     if (id==0) id = w2ui.sidebar.selected
     fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "get_data", "id": id}})
    }).then(response => response.json())
    .then(result => {
        let main = w2ui.layout.get('main')
        let data = document.getElementById('dataGrid')
        data.style.display = 'block'
        data.style.height=(main.height - 50).toString() + "px"
        let grid = w2ui.data_grid
        grid.columns = result.result.columns
        grid.records = result.result.records
        grid.render("#dataGrid")
        grid.refresh()
    })
    .catch(error => console.error('Error:', error))
}


function refreshMeta(){
    fetch('/db', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "db", "params":{"do": "get_db_objects"}})
    }).then(response => response.json())
    .then(result => {
          let sel = null
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
    .catch(error => console.error('Error:', error))
}

function getNodeInfo(id){
    w2ui.layout.get('main').tabs.disable('data')
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "get_info", "id": id}})
    }).then(response => response.json())
    .then(result => {
        let tabs = w2ui.layout.get('main').tabs
        window.info_editor.setValue(result.result)
        if("tv".includes(id[0])) {
            w2ui.layout.get('main').tabs.enable('data')
        } else
        if(tabs.active == "data") tabs.click("info")
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
   })

   refreshMeta()
}

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
        body: JSON.stringify({"method": "db", "params":{"do": "sql", "sql_b64": btoa(sql_text)}})
    }).then(response => response.json())
    .then(result => {
        let data = document.getElementById("previewData")
        let error = document.getElementById("previewError")
        let notify = document.getElementById("previewNotify")
        let notify_text = document.getElementById("previewNotifyText")
        let table = document.getElementById("previewTable")
        error.style.display = "none"
        data.style.display = "block"
        table.style.display = "none"
        notify.style.display = "block"

        notify_text.innerText = result.result.notice
        if ("columns" in result.result) {
            w2ui.previewToolbar.enable("data")
            w2ui.result_grid.columns = result.result.columns
            w2ui.result_grid.records = result.result.records
            w2ui.result_grid.render("#previewTable")

            setTimeout(
              () => {
                w2ui.previewToolbar.click("data")
                w2ui.result_grid.refresh()
              },
              500
            )
        } else {
            w2ui.previewToolbar.disable("data")
        }
        w2ui.layout.show("preview")
    })
    .catch(error => console.error('Error:', error))
}