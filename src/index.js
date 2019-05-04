const app = require('express')()
const port = 3000

app.get('/', (req,res)=>{
	console.log('someone accessing \'/\' path')
	res.send('Hello World!!\nI made a change again :)!')
})

app.listen(port,()=>console.log(`Example app listening on port ${port}`))
