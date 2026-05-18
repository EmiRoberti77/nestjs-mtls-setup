import axios from 'axios';
import * as https from 'https';
import * as fs from 'fs';
import * as path from 'path';

const __root = path.join(__dirname)

async function main() {  
    console.log('root', __root)
    const agent = new https.Agent({
        ca: fs.readFileSync(path.join(__root, '..', '..', 'certs', 'ca.crt')),
        cert: fs.readFileSync(path.join(__root, '..', '..', 'certs', 'client.crt')),
        key: fs.readFileSync(path.join(__root, '..', '..', 'certs', 'client.key')),
        rejectUnauthorized: true,
    });

    const res = await axios.get('https://localhost:3000', {
        httpsAgent: agent,
    });

    console.log(res.data);
}

main().catch(console.error);