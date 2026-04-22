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
                      info.style.display = 'none'
                      cons.style.display = 'none'
                      data.style.display = 'none'
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
            html: `<div id="infoEditor" style="full"></div>
                   <div id="consoleEditor" style="full" hidden></div>
                   <div id="dataGrid" style="width: 100%, ;height: 100%; background-color: #f0f0f0" hidden></div>`
        }
     ]
 })


new w2sidebar({
    topHTML: `<div style="background-color: #eee; padding: 10px 5px; border-bottom: 1px solid silver">
    <button class="w2ui-btn action">
     <i class="fas fa-refresh"></i>
    </button>
    <button class="w2ui-btn action">
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
    fetch('/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "db", "params":{"do": "get_db_objects"}})
    }).then(response => response.json())
    .then(result => {
          let sidebar= w2ui.sidebar
          let nodeIds = sidebar.nodes.map(n => n.id)
          sidebar.remove.apply(sidebar, nodeIds)
          result.result.forEach((item)=>{
            sidebar.add(item)
          })
          sidebar.refresh();
    })
    .catch(error => console.error('Error:', error));
}

function getNodeInfo(id){
  fetch('/api', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({"method": "db", "params":{"do": "get_info", "id": id}})
      }).then(response => response.json())
      .then(result => {
            window.info_editor.setValue(result.result);
      })
      .catch(error => console.error('Error:', error));
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

