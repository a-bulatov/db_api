const pstyle = 'border: 1px solid #efefef; padding: 5px'
const lineMarks = []
let debug_id = 0
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
                      clearMarks()
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
                    {{DBG_API}}
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
                stopDebug()
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
                    fieldPopup(val, this.columns[column].text)
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
                fieldPopup(val, this.columns[column].text)
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
    menu: [],
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
    },
    onContextMenu(event) {
         //const targetId = event.target;
         const targetId = w2ui.sidebar.selected;
         if (targetId == 'db') {
             this.menu = [
                 {{FL_MENU}}
                 { id: 'ptrn.gen', text: 'Создать шаблон', icon: 'fa fa-cube' },
                 { id: 'ptrn.chk', text: 'Сравнить шаблон', icon: 'fa fa-exchange' },
                 { text: '--' },
                 { id: 'model.gen', text: 'Модель данных', icon: 'fa fa-th' },
                 { text: '--' },
                 { id: 'refresh', text: 'Обновить', icon: 'fa fa-refresh' }
             ]
         } else if (targetId.startsWith('sh.')) {
             this.menu = [
                  { id: 'model.gen', text: 'Модель данных', icon: 'fa fa-th' },
                  { text: '--' },
                  { id: 'refresh', text: 'Обновить', icon: 'fa fa-refresh' }
             ]
         } else {
             this.menu = []
         }
    },
    onMenuClick(event) {
         switch(event.detail.menuItem.id) {
           case "init.load":
               loadScript()
               break
           case "init.save":
               w2confirm('Сохранение скрипта приведет к замене скрипта инициализации БД!<br>Отменить сохранение скрипта?')
                   .yes(() => {})
                   .no(saveScript)
               break
           case "ptrn.gen":
               createPattern()
               break
           case "ptrn.chk":
               document.getElementById('patternFile').click()
               break
           case "refresh":
               refreshMeta()
               break
           case "model.gen":
               const btn = document.getElementById(`modelBtn`)
               btn.click()
               break
         }
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

function fieldPopup(text, title="Значение:") {

    // try {
    //    text = JSON.stringify(text, null, 4)
    //} catch(err) {
        text = String(text)
    //}

    text = text.replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\"/g, '"')

    w2popup.open({
        title: title,
        body: '<div style="padding:10px"><pre>' + text + '</pre></div>',
        showMax: true,
        blockPage: false,
        resizable: true,
    })
}


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

function loadScript() {
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "load_script"}})
    }).then(response => response.json())
    .then(result => {
        let editor = w2ui.layout.get("main").tabs.active == "info" ? window.info_editor : window.console_editor
        editor.setValue(result.result)
    })
    .catch(error => console.error('Error:', error))
}

async function saveFunction() {
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

function saveScript() {
    let sql_text = (w2ui.layout.get("main").tabs.active == "info" ? window.info_editor : window.console_editor).getValue()
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "save_script", "sql_b64": btoa(unescape(encodeURIComponent(sql_text)))}})
    }).then(response => response.json())
    .then(result => {
        w2utils.notify('Ok', {timeout: 2000, success: true, top: 20, right: 20})
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

function clearMarks() {
    lineMarks.forEach(m => m.clear())
    lineMarks.length = 0
}

function refreshMeta(){
    clearMarks()
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

          window.console_editor.setOption("hintOptions",{"tables":result.result.tables})
          window.info_editor.setOption("hintOptions",{"tables":result.result.tables})

          let tabs = w2ui.layout.get('main').tabs
          if (tabs) tabs.click(tabs.active)
    })
    .catch(error => console.error('Error:', error))
}

function runClick() {
    clearMarks()
    let editor = w2ui.layout.get("main").tabs.active == "console" ? window.console_editor  : window.info_editor
    let sql_text = editor.getSelection()
    let ctx = true
    if(sql_text == "") {
        ctx = false
        sql_text = editor.getValue()
    }
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
        if (Object.hasOwn(result.result, "line") && !ctx) {
            const mark = editor.markText(
              { line: result.result.line - 1, ch: 0 }, // начало выделения {строка, символ в строке}
              { line: result.result.line - 1, ch: editor.getLine(result.result.line - 1).length }, // конец выделения
              { className: 'cm-error-line' })
            lineMarks.push(mark)
        }
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
            case "end":
               notify.innerHTML += 'Выполнение завершено!'
               break
        }
    };
}

function createPattern() {
	let el = document.getElementById("layout_layout_panel_left")
    w2utils.lock(el, { spinner: true, msg: 'Создание шаблона...' })
    fetch('/db', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "save_struct"}})
    }).then(response => response.json())
    .then(result => {
        const blob = new Blob([result.result], { type: 'text/plain' })
        const url = URL.createObjectURL(blob)
        const link = document.createElement('a')
        link.href = url
        link.download = 'db_pattern.yaml'
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
        URL.revokeObjectURL(url)
        w2utils.unlock(el)
    })
    .catch(error => {console.error('Error:', error), w2utils.unlock(el)})
}

function checkPattern(fl_input) {
	const file = fl_input.target.files[0]
    if (!file) return

    const reader = new FileReader()

    reader.onload = function(event) {
        let el = document.getElementById("layout_layout_panel_left")
        w2utils.lock(el, { spinner: true, msg: 'Сравнивание шаблона...' })
        fetch('/db', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({"method": "db", "params":{"do": "check_struct", "data_64": btoa(unescape(encodeURIComponent(event.target.result)))}})
        }).then(response => response.json())
        .then(result => {
            let editor = w2ui.layout.get("main").tabs.active == "console" ? window.console_editor  : window.info_editor
            editor.setValue(result.result)
            w2utils.unlock(el)
        })
        .catch(error => {console.error('Error:', error), w2utils.unlock(el)})
    }

    reader.onerror = function() {
        console.error('Ошибка чтения файла')
    }

    reader.readAsText(file)
}

function openModel() {
	window.open(`/db?model=${w2ui.sidebar.selected}`);
}

function startDebug(){
    w2ui.layout.hideTabs('main')
    w2ui.layout.hide("left")
    let start_dbg = document.getElementById("funcExts")
    start_dbg.style.display = 'none'
    window.info_editor.setOption('readOnly', 'nocursor')
    let data = document.getElementById("previewData")
    let error = document.getElementById("previewError")
    let notify = document.getElementById("previewNotify")
    let table = document.getElementById("previewTable")
    error.style.display = "none"
    data.style.display = "block"
    table.style.display = "none"
    notify.style.display = "block"
    w2ui.result_grid.columns = [
       { field: 'key', text: 'Переменная', size: '30%' },
       { field: 'value', text: 'Значение', size: '100%' }
    ]
    w2ui.result_grid.records = [{"key":"","value":""}]
    w2ui.layout.show("preview")
    w2ui.result_grid.render("#previewTable")
    debug_id = 1
}

function stopDebug() {
    w2ui.layout.hide('preview')
    if(debug_id == 0) return
    w2ui.layout.showTabs('main')
    w2ui.layout.show("left")
    window.info_editor.setOption('readOnly', false)
    let start_dbg = document.getElementById("funcExts")
    start_dbg.style.display = 'block'
    debug_id == 0
}

//----------------------------------------------------------------------------------------

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

   document.getElementById('patternFile').addEventListener('change', checkPattern)

   refreshMeta()
}