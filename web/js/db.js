let pstyle = 'border: 1px solid #efefef; padding: 5px';
let layout = new w2layout({
     box: '#layout',
     name: 'layout',
     panels: [
         { type: 'left', resizable: true, size: 200, style: pstyle, html: 'left' },
         { type: 'main', resizable: true, style: pstyle,
            tabs: {
                 name: 'tabs',
                 active: 'tab1',
                 tabs: [
                     { id: 'tab1', text: 'Определение' },
                     { id: 'tab2', text: 'Консоль' },
                     { id: 'tab3', text: 'Данные' },
                 ],
                 onClick(event) {
                     if (event.target === 'tab1') {
                         this.owner.html('main', '<div style="padding: 10px">General Info Content</div>');
                     } else if (event.target === 'tab2') {
                         this.owner.html('main', grid); // Load a w2ui object
                     }
                 }
           }
         }
     ]
 })

let grid = new w2grid({
    name: 'myGrid',
    columns: [{ field: 'name', text: 'Name', size: '100%' }],
    records: [{ recid: 1, name: 'John Doe' }]
});

let sidebar = new w2sidebar({
    name: 'sidebar',
    topHTML: '<div style="background-color: #eee; padding: 10px 5px; border-bottom: 1px solid silver">Some HTML</div>',
    nodes: [],
    onClick: function (event) {
        console.log(event.target);
    }
});
layout.html('left', w2ui.sidebar);

function refreshMeta(){
    fetch('/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "db", "params":{"do": "get_db_objects"}})
    }).then(response => response.json())
    .then(result => {
          let nodeIds = sidebar.nodes.map(n => n.id)
          sidebar.remove.apply(sidebar, nodeIds)
          result.result.forEach((item)=>{
            sidebar.add(item)
          })
          sidebar.refresh();
    })
    .catch(error => console.error('Error:', error));
}


refreshMeta();
