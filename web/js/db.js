const pstyle = 'border: 1px solid #efefef; padding: 5px'
document.addEventListener('mousemove', function(e) { window._lastMouse = e })
const editor_conf = {
       //theme: 'idea',
       mode: 'text/x-pgsql',
       lineNumbers: true,
       indentWithTabs: true,
       smartIndent: true,
       lineWrapping: true,
       autofocus: true,
       indentUnit: 2,
        tabSize: 4,
        dragDrop: false,
        extraKeys: { "Ctrl-Space": function(cm){cm.showHint();}, "Shift-Tab": "indentLess" },
       hintOptions: { tables: [], completeSingle: false }
    }


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
                      run_btn.disabled = event.target == "data"
                 }
            },
            html: `
                <div id="infoEditor" class="full">
                    <div id="funcExts" class="custom-rt" hidden>
                    {{FN_SAVE}}
                    <button id="fn-debug" class="w2ui-btn action" onclick="run()" title="Отладка"><i class="fas fa-bug"></i></button>
                    </div>
                </div>
                <div id="consoleEditor" class="full" hidden></div>
                <div id="dataGrid" class="full" hidden></div>`
         },
         { type: 'preview', size: '50%', resizable: true, hidden: true, style: pstyle, html: `
            <div id="previewError" style="full" hidden></div>
            <div id="previewData" class="tabs" hidden>
              <div id="previewToolbar"></div>
              <div class="full" hidden id="previewNotify"></div>
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
        { type: 'button', id: 'save', text: 'Выгрузить', icon: 'w2ui-icon-paste' },
        { type: 'button', id: 'close', text: 'Закрыть', icon: 'fa fa-times' }
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
            case ('close') :
                w2ui.layout.hide('preview')
                break
        }
    }
})

new w2grid({
   name: 'result_grid',
   box:'#previewTable',
   contextMenu: [
         { id: 'refresh', text: 'Обновить', icon: 'w2ui-icon-empty' },
         { text: '--' },
         { id: 'clipbrd', text: 'Поле в буфер', icon: 'w2ui-icon-pencil' },
         { id: 'view', text: 'Показать', icon: 'w2ui-icon-info' },
     ],
     onContextMenuClick(event) {
         let { recid, column, index } = event.detail
         let val = this.getCellCopy(recid, column)
         switch(event.detail.menuItem.id) {
               case "refresh":
                   runClick()
                   break
               case "clipbrd":
                   copyToClipboard(String(val))
                   break
               case "view":
                   w2popup.open({
                       title: this.columns[column].text,
                       text: String(val),
                       resizable: true
                   })
                   break
         }
     },
   columns: [
   ],
   records: [
   ]})

new w2grid({
  name: 'data_grid',
  box:"#dataGrid",
  show: { lineNumbers: true },
  contextMenu: [
      { id: 'refresh', text: 'Обновить', icon: 'w2ui-icon-empty' },
      { text: '--' },
      { id: 'clipbrd', text: 'Поле в буфер', icon: 'w2ui-icon-pencil' },
      { id: 'view', text: 'Показать', icon: 'w2ui-icon-info' },
  ],
  onContextMenuClick(event) {
      let { recid, column, index } = event.detail
      let val = this.getCellCopy(recid, column)
      switch(event.detail.menuItem.id) {
            case "refresh":
                refreshData()
                break
            case "clipbrd":
                copyToClipboard(String(val))
                break
            case "view":
                w2popup.open({
                    title: this.columns[column].text,
                    text: String(val),
                    resizable: true
                })
                break
      }
  },
  columns: [
  ],
  records: [
  ]})

new w2sidebar({
    topHTML: `<div style="background-color: #eee; padding: 10px 5px; border-bottom: 1px solid silver">
    <button class="w2ui-btn action" onclick="refreshMeta()">
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
    onMouseEnter: function(event) {
        var node = this.get(event.target);
        if (!node || !node.tooltip) return;
        var e = event.originalEvent;
        if (!e && window._lastMouse) e = window._lastMouse;
        if (!e) return;
        var tip = document.getElementById('sb_tip');
        if (!tip) {
            tip = document.createElement('div');
            tip.id = 'sb_tip';
            tip.style.cssText = 'position:fixed;z-index:99999;background:#fff;color:#000;' +
                'padding:4px 8px;border-radius:3px;font-size:12px;pointer-events:none;display:none;' +
                'border:1px solid #ccc;box-shadow:1px 2px 4px rgba(0,0,0,.1)';
            document.body.appendChild(tip);
        }
        tip.textContent = node.tooltip;
        tip.style.display = '';
        tip.style.left = (e.clientX + 12) + 'px';
        tip.style.top = (e.clientY + 10) + 'px';
    },
    onMouseLeave: function() {
        var tip = document.getElementById('sb_tip');
        if (tip) tip.style.display = 'none';
    }
})

w2ui.layout.html('left', w2ui.sidebar)

// drag из sidebar
document.addEventListener('mousedown', function(e) {
    var nodeEl = e.target.closest('.w2ui-node')
    if (nodeEl) {
        var id = nodeEl.id.replace('node_', '')
        var node = w2ui.sidebar.get(id)
        if (node && node.icon !== 'fa fa-computer') nodeEl.draggable = true
    }
})

document.addEventListener('dragstart', function(e) {
    var nodeEl = e.target.closest('.w2ui-node')
    if (!nodeEl) return
    var id = nodeEl.id.replace('node_', '')
    var node = w2ui.sidebar.get(id)
    if (node && node.text && node.icon !== 'fa fa-computer') {
        e.dataTransfer.setData('text/plain', node.text)
        e.dataTransfer.effectAllowed = 'copy'
    }
})

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
        let fexts = document.getElementById('funcExts')
        window.info_editor.setValue(result.result)
        if(id.startsWith("fn.")) {
            fexts.style.display = 'block'
        } else {
            fexts.style.display='none'
        }
        if("tv".includes(id[0])) {
            w2ui.layout.get('main').tabs.enable('data')
        } else
        if(tabs.active == "data") tabs.click("info")
    })
    .catch(error => console.error('Error:', error))
}

function AutocompleteTrigger(cm, change) {
    if (change && change.text && change.text[0] && (change.text[0] === ' ' || change.text[0] === '.')) {
        setTimeout(function() {
            cm.showHint();
        }, 10);
    }
}

window.onload = function() {
   window.info_editor = CodeMirror(document.getElementById('infoEditor'), Object.assign({},editor_conf))
   window.console_editor = CodeMirror(document.getElementById('consoleEditor'), Object.assign({},editor_conf,{autofocus:false}))
   window.info_editor.on("inputRead", AutocompleteTrigger)
   window.console_editor.on("inputRead", AutocompleteTrigger)

   // drag-drop из sidebar в редакторы codemirror
   function setupDragDrop(cm) {
       var wr = cm.getWrapperElement()
       wr.addEventListener('dragover', function(e) { e.preventDefault() })
       wr.addEventListener('drop', function(e) {
           e.preventDefault()
           var text = e.dataTransfer.getData('text/plain')
           if (text) {
               var pos = cm.coordsChar({left:e.clientX, top:e.clientY}, 'window')
               cm.replaceRange(text, pos)
               cm.focus()
               cm.setCursor({line:pos.line, ch:pos.ch + text.length})
           }
       })
   }
   setupDragDrop(window.info_editor)
   setupDragDrop(window.console_editor)

   refreshMeta()
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
          if (sidebar.nodes.length > 0 && sidebar.selected !== null) sel=sidebar.selected[0]
          let nodeIds = sidebar.nodes.map(n => n.id)
          sidebar.remove.apply(sidebar, nodeIds)
          result.result.sidebar.forEach((item)=>{
            sidebar.add(item)
          })
          if (sel === null) sel = result.result.sidebar[0]["id"]
          sidebar.refresh()
          sidebar.click(sel)
          let tabs = w2ui.layout.get('main').tabs
          tabs.click(tabs.active)
          window.console_editor.setOption("hintOptions",{"tables":result.result.tables})
          window.info_editor.setOption("hintOptions",{"tables":result.result.tables})
    })
    .catch(error => console.error('Error:', error))
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
        body: JSON.stringify({"method": "db", "params":{"do": "sql", "sql_b64": btoa(unescape(encodeURIComponent(sql_text)))}})
    }).then(response => response.json())
    .then(result => {
        let data = document.getElementById("previewData")
        let error = document.getElementById("previewError")
        let notify = document.getElementById("previewNotify")
        let table = document.getElementById("previewTable")
        error.style.display = "none"
        data.style.display = "block"
        table.style.display = "none"
        notify.style.display = "block"

        if (result.result.id !== undefined && result.result.id !== null) {
            w2ui.layout.show("preview")
            multiQuery(result.result.id)
            return
        }

        notify.innerHTML = result.result.notice
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

async function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    await navigator.clipboard.writeText(text)
  } else {
    const textArea = document.createElement("textarea")
    textArea.value = text
    document.body.appendChild(textArea)
    textArea.select()
    document.execCommand("copy")
    document.body.removeChild(textArea)
  }
}

async function saveFnunction() {
    let sql_text = window.info_editor.getValue()
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "save_fn", "sql_b64": btoa(unescape(encodeURIComponent(sql_text)))}})
    }).then(response => response.json())
    .then(result => {
        w2utils.notify('Ok', {timeout: 2000, success: true, top: 20, right: 20})
    })
    .catch(error => console.error('Error:', error))
}

function multiQuery(id) {
    let notify = document.getElementById("previewNotify")
    notify.innerHTML = ""
    w2ui.previewToolbar.disable("data")
    const eventSource = new EventSource('/db?sql='+id);

    eventSource.onerror = function() {
        eventSource.close();
    };

    eventSource.onmessage = function(event) {
        let data = JSON.parse(event.data)
        switch(data.type){
            case "query":
                notify.innerHTML += '<br><b>' + data.val + '</b><br>'
                break
            case "ok":
                notify.innerHTML += '<p style="color: green;">Ok</p>' + data.val + '<hr><br>'
                break
            case "ret":
                if (typeof data.val === 'string') {
                     notify.innerHTML += data.val + '<br>'
                } else {
                    w2ui.previewToolbar.enable("data")
                    w2ui.result_grid.columns = data.val.columns
                    w2ui.result_grid.records =data.val.records
                    w2ui.result_grid.render("#previewTable")
                }
                break
            case "error":
               notify.innerHTML += '<p style="color: red;">ERROR</p>' + data.val + '<hr><br>'
               break
        }
    };
}