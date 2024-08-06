const express = require("express");
// verbose 모드 활성화 -> sqlite 관련 디버깅 출력 도와줌
const sqlite3 = require('sqlite3').verbose();  
// 파일 시스템 사용
const fs = require('fs');
// 암호화 모듈 bcrypt
const bcrypt = require('bcrypt'); 
// 랜덤 문자열 id 생성
const uuid = require('uuid');
// 이미지 파일 처리
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const bodyParser = require('body-parser');
const app = express();
const port=3000;
const saltRounds = 10;  // 해싱넘버

// SQLite 데이터베이스 연결
const db = new sqlite3.Database('./db/sqlite.db', (err) => {
    if (err) {
        console.error('데이터베이스 연결 실패', err.message);
    } else {
        console.log('데이터베이스 연결 성공');
    }
});

const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        // 파일을 저장할 디렉토리 설정
        const userDir = path.join(__dirname, 'Users', req.body.userId, 'Data', 'media');
        fs.mkdir(userDir, { recursive: true }, (err) => {
            if (err) return cb(err);
            cb(null, userDir);
        });
    },
    filename: function (req, file, cb) {
        // 파일 이름 설정
        cb(null, `${uuid.v4()}${path.extname(file.originalname)}`);
    }
});

const upload = multer({ storage: storage });

// 미들웨어 설정 -> json 형태 데이터 허용
app.use(bodyParser.json());

// 50MB로 설정 (필요에 따라 조정)
app.use(bodyParser.json({ limit: '50mb' }));  

app.use(cors());

// 로그인 API
app.post('/login', (req, res) => {
    const { user_id, user_pw } = req.body;

    // 입력 검증
    if (!user_id || !user_pw) {
        return res.status(400).json({ error: '전화번호와 비밀번호를 입력하세요.'});
    }

    // 유저 정보 조회
    db.get('SELECT user_pw FROM User WHERE user_id = ?', [user_id], async (err, row) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류'});
        }
        if (!row) {

            return res.status(401).json({ error: '해당 전화번호의 유저가 없습니다.'});
        }
        // 비밀번호 검증
        try {
            const isMatch = await bcrypt.compare(user_pw, row.user_pw);
            if (isMatch) {
                res.status(200).json({ message: '로그인 성공' });
                console.log(`user:${user_id} 님이 접속 했습니다.`);
            } else {
                res.status(401).json({ error: '비밀번호를 다시 확인하세요.'});
            }
        } catch (error) {
            res.status(500).json({ error: '비밀번호 비교 오류' });
        }
    });
});

// 회원가입 API
app.post('/signup', (req, res) => {
    const { user_id, user_pw, user_name } = req.body;

    // 입력 검증
    if (!user_id || !user_pw || !user_name) {
        return res.status(400).json({ error: '전화번호, 비밀번호, 이름을 입력하세요.'});
    }

    // 비밀번호는 4자리 숫자여야 함
    if (!/^\d{4}$/.test(user_pw)) {
        return res.status(400).json({ error: '비밀번호는 4자리 숫자여야 합니다.'});
    }

    // 중복 사용자 체크
    db.get('SELECT user_id FROM User WHERE user_id = ?', [user_id], (err, row) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류'});
        }
        if (row) {
            return res.status(409).json({ error: '이미 존재하는 전화번호입니다.'});
        }
        // 비밀번호 해싱
        bcrypt.hash(user_pw, saltRounds, (err, hashedPassword) => {
            if (err) {
                return res.status(500).json({ error: '비밀번호 해싱 오류'});
            }
            // 데이터베이스에 사용자 정보 저장
            db.run('INSERT INTO User (user_id, user_pw, user_name) VALUES (?, ?, ?)', [user_id, hashedPassword, user_name], function(err) {
                if (err) {
                    return res.status(500).json({ error: '데이터베이스 삽입 오류'});
                }

                const userDir = path.join(__dirname, './Users', user_id);
                const dataDir = path.join(userDir, 'Data');
                const mediaDir = path.join(dataDir, 'media');
                const txtDir = path.join(dataDir, 'txt');
            
                fs.mkdir(userDir, { recursive: true }, (err) => {
                    if (err) {
                        console.error('디렉토리 생성 오류', err.message);
                        return res.status(500).json({ error: '디렉토리 생성 오류'});
                    }
                    fs.mkdir(dataDir, { recursive: true }, (err) => {
                        if (err) {
                            console.error('Data 디렉토리 생성 오류', err.message);
                            return res.status(500).json({ error: 'Data 디렉토리 생성 오류'});
                        }
                        fs.mkdir(mediaDir, { recursive: true }, (err) => {
                            if (err) {
                                console.error('media 디렉토리 생성 오류', err.message);
                                return res.status(500).json({ error: 'media 디렉토리 생성 오류'});
                            }
                            // txt 디렉토리 생성
                            fs.mkdir(txtDir, { recursive: true }, (err) => {
                                if (err) {
                                    console.error('txt 디렉토리 생성 오류', err.message);
                                    return res.status(500).json({ error: 'txt 디렉토리 생성 오류'});
                                }

                                res.status(201).json({ message: '회원가입 성공'});
                                console.log(`user_id:${user_id}, user_name:${user_name} 님이 회원가입 했습니다.`);
                            });
                        });
                    });
                });
            });
        });
    });
});


// text 데이터 post
app.post('/data', (req, res) => {
    const { userId, format, isOpen, theme, posX, posY, width, height, data_txt } = req.body;
    const date = new Date().toISOString();
    const dataId = uuid.v4();  // UUID 생성
    const userDir = path.join(__dirname, 'Users', userId, 'Data', 'txt');
    const filePath = path.join(userDir, `${dataId}.txt`); // 템플릿 리터럴 수정
    // 디렉토리가 존재하지 않으면 생성
    fs.mkdir(userDir, { recursive: true }, (err) => {
        if (err) {
            return res.status(500).json({ error: '디렉토리 생성 오류', message: err.message });
        }
        // 파일에 데이터 쓰기
        fs.writeFile(filePath, data_txt, (err) => {
            if (err) {
                return res.status(500).json({ error: '파일 쓰기 오류', message: err.message });
            }
            // 데이터베이스에 UUID와 기타 정보를 삽입
            db.run(
                `INSERT INTO Data (dataId, userId, path, format, date, isOpen, theme, posX, posY, width, height, data_txt) 
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [dataId, userId, filePath, format, date, isOpen, theme, posX, posY, width, height, data_txt],
                function(err) {
                    if (err) {
                        return res.status(500).json({ error: '데이터베이스 삽입 오류', message: err.message });
                    }
                    res.status(201).json({ message: '데이터가 성공적으로 저장되었습니다.' });
                    console.log(`userId:${userId} 님이 데이터를 저장했습니다. 파일 경로: ${filePath}`); // 템플릿 리터럴 수정
                }
            );
        });
    });
});

// 파일 업로드 API
app.post('/upload', upload.single('file'), (req, res) => {
    const { userId, format, isOpen, theme, posX, posY, width, height } = req.body;
    const file = req.file;
    if (!file) {
        return res.status(400).json({ error: '파일이 업로드되지 않았습니다.' });
    }
    const date = new Date().toISOString();
    const dataId = file.filename;  
    const filePath = path.join('Users', userId, 'Data', 'media', file.filename);
    // 데이터베이스에 정보 삽입
    db.run(
        `INSERT INTO Data (dataId, userId, path, format, date, isOpen, theme, posX, posY, width, height, data_txt) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [dataId, userId, filePath, format, date, isOpen, theme, posX, posY, width, height, null],
        function (err) {
            if (err) {
                console.error('데이터베이스 삽입 오류', err.message);
                return res.status(500).json({ error: '데이터베이스 삽입 오류', message: err.message });
            }
            res.status(201).json({ message: '데이터가 성공적으로 저장되었습니다.' });
            console.log(`userId: ${userId} 님이 데이터를 저장했습니다. 파일 경로: ${filePath}`);
        }
    );
});

// 파일 제공
app.get('/media/:userId/:fileName', (req, res) => {
    const { userId, fileName } = req.params;
    const filePath = path.join(__dirname, 'Users', userId, 'Data', 'media', fileName);
    res.sendFile(filePath, (err) => {
        if (err) {
            res.status(404).json({ error: '파일을 찾을 수 없습니다.', message: err.message });
        }
    });
});

// userId로 모든 데이터를 가져오는 api
app.get('/data/:user_id', (req, res) => {
    const userId = req.params.user_id; 
    db.all('SELECT dataId, path, format, date, isOpen, theme, posX, posY, width, height, data_txt FROM Data WHERE userId = ?', [userId], (err, rows) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류', message: err.message });
        }
        res.status(200).json(rows);
    });
});


app.delete('/data/:dataId', (req, res) => {
    const dataId = req.params.dataId;
    db.get('SELECT path FROM Data WHERE dataId = ?', [dataId], (err, row) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류' });
        }
        if (!row) {
            return res.status(404).json({ error: '데이터를 찾을 수 없습니다.' });
        }

        // 파일 삭제
        fs.unlink(row.path, (err) => {
            if (err) {
                console.error('파일 삭제 오류:', err);
                return res.status(500).json({ error: '파일 삭제 실패' });
            }
            console.log('파일 삭제 성공');
            
            // 데이터베이스에서 데이터 삭제
            db.run('DELETE FROM Data WHERE dataId = ?', [dataId], function(err) {
                if (err) {
                    return res.status(500).json({ error: '데이터베이스 삭제 오류' });
                }
                res.status(200).json({ message: '데이터와 파일이 성공적으로 삭제되었습니다.' });
            });
        });
    });
});

// 사용자 검색 API 
app.get('/searchUser/:user_id/:friend_user_id', (req, res) => {
    const user_id = req.params.user_id;
    const friend_user_id = req.params.friend_user_id;
    // 자기 자신을 친구로 추가할 수 없음
    if (user_id === friend_user_id) {
        return res.status(400).json({ error: '자기 자신을 친구로 추가할 수 없습니다.' });
    }
    // 사용자 존재 여부 체크
    db.get('SELECT user_id, user_name FROM User WHERE user_id = ?', [friend_user_id], (err, userRow) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류' });
        }
        if (!userRow) {
            return res.status(404).json({ error: '해당 사용자 ID를 찾을 수 없습니다.' });
        }
        // 친구 관계 중복 체크
        db.get('SELECT * FROM Friend WHERE user_id = ? AND friend_user_id = ?', [user_id, friend_user_id], (err, friendRow) => {
            if (err) {
                return res.status(500).json({ error: '데이터베이스 쿼리 오류' });
            }
            if (friendRow) {
                return res.status(409).json({ error: '이미 친구 관계입니다.' });
            }
            // 찾은 user의 아이디와 이름 반환
            res.status(200).json({ user_id: userRow.user_id, user_name: userRow.user_name });
        });
    });
});


// 친구 추가 API
app.post('/friend', (req, res) => {
    const { user_id, friend_user_id } = req.body;
    // 입력 검증
    if (!user_id || !friend_user_id) {
        return res.status(400).json({ error: 'user_id와 friend_user_id를 입력하세요.' });
    }
    // 자기 자신을 친구로 추가할 수 없음
    if (user_id === friend_user_id) {
        return res.status(400).json({ error: '자기 자신을 친구로 추가할 수 없습니다.' });
    }
    // 친구 관계 추가
    db.get('SELECT * FROM Friend WHERE user_id = ? AND friend_user_id = ?', [user_id, friend_user_id], (err, friendRow) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류' });
        }
        if (friendRow) {
            return res.status(409).json({ error: '이미 친구 관계입니다.' });
        }

        // 친구 관계 추가
        db.run('INSERT INTO Friend (user_id, friend_user_id) VALUES (?, ?)', [user_id, friend_user_id], function (err) {
            if (err) {
                return res.status(500).json({ error: '없는 유저의 아이디 입니다.' });
            }
            res.status(201).json({ message: '친구 추가 성공' });
            console.log(`user_id:${user_id} 님이 friend_user_id:${friend_user_id} 님을 친구로 추가했습니다.`);
        });
    });
});

// 친구 목록 조회 => user의 친구 id와 이름을 query로
app.get('/friends/:user_id', (req, res) => {
    const user_id = req.params.user_id;
    const query = `
        SELECT u.user_id, u.user_name 
        FROM Friend f 
        JOIN User u ON f.friend_user_id = u.user_id 
        WHERE f.user_id = ?
    `;
    db.all(query, [user_id], (err, rows) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류', message: err.message });
        }
        res.status(200).json(rows);
    });
});

// 친구 삭제 API
app.delete('/friend', (req, res) => {
    const { user_id, friend_user_id } = req.body;

    if (!user_id || !friend_user_id) {
        return res.status(400).json({ error: 'user_id와 friend_user_id를 입력하세요.' });
    }
    console.log(`user_id:${user_id} 님이 friend_user_id:${friend_user_id}.`);

    // 친구 관계 존재 여부 확인
    db.get('SELECT * FROM Friend WHERE user_id = ? AND friend_user_id = ?', [user_id, friend_user_id], (err, friendRow) => {
        if (err) {
            return res.status(500).json({ error: '데이터베이스 쿼리 오류' });
        }
        if (!friendRow) {
            return res.status(404).json({ error: '친구 관계가 존재하지 않습니다.' });
        }

        // 친구 관계 삭제
        db.run('DELETE FROM Friend WHERE user_id = ? AND friend_user_id = ?', [user_id, friend_user_id], function (err) {
            if (err) {
                return res.status(500).json({ error: '데이터베이스 삭제 오류' });
            }
            res.status(200).json({ message: '친구 삭제 성공' });
            console.log(`user_id:${user_id} 님이 friend_user_id:${friend_user_id} 님을 친구에서 삭제했습니다.`);
        });
    });
});


app.listen(port, ()=>{
    console.log(`서버 오픈 포트번호:${port}`);
})
