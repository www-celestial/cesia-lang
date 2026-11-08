// COUNT async functions park on one promise, then all end once it resolves.
const count = Number(process.argv[2]);
let open;
const gate = new Promise(resolve => { open = resolve; });
const tasks = [];
for (let i = 0; i < count; i++) tasks.push((async () => { await gate; })());
open();
Promise.all(tasks).then(() => console.log(count));
