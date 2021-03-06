from response import ResponseObj
from response import RequestHandler
import traceback
import globalsObj
import jwtoken.lib.jwtoken

class jwtokenHandler(RequestHandler):

    def __init__(self, *args, **kwds):
        super(RequestHandler, self).__init__(*args, **kwds)
        self.dbobjJwt = globalsObj.DbConnections['jwtDb']

    def set_default_headers(self):
        self.set_header("Access-Control-Allow-Origin", "*")
        self.set_header('Access-Control-Allow-Methods', '*')

    # gestione errore generico
    def write_error(self, status_code, **kwargs):

        # debug info
        if self.settings.get("serve_traceback") and "exc_info" in kwargs:
            debugTmp = ""
            for line in traceback.format_exception(*kwargs["exc_info"]):
                debugTmp += line
            getResponse = ResponseObj(debugMessage=debugTmp,httpcode=status_code,devMessage=self._reason)
        else:
            getResponse = ResponseObj(httpcode=status_code,devMessage=self._reason)

        self.set_header('Content-Type', 'application/json; charset=UTF-8')
        self.set_status(status_code)

        # inserisci codice errore personalizzato
        getResponse.setError('3')
        getResponse.setResult()
        self.write(getResponse.jsonWrite())
        self.finish()

    def writeResponse(self, response_obj):

        self.set_status(response_obj.error.httpcode)
        self.write(response_obj.jsonWrite())
        self.finish()

    async def writeLog(self, response_obj):
        x_real_ip = self.request.headers.get(globalsObj.jwtoken_originIP_header)
        remote_ip = x_real_ip or self.request.remote_ip

        #insert log
        if str(self.request.body, 'utf-8') == '':
            body = 'NULL'
        else:
            body = "'"+str(self.request.body, 'utf-8').replace("'", "''")+"'"

        log_request = await self.dbobjJwt.execute_statment("log_request('%s', '%s', %s, '%s')" %
                        (self.request.method,
                        self.request.protocol + "://" + self.request.host + self.request.uri,
                        body,
                        remote_ip))

        log_response = await self.dbobjJwt.execute_statment("log_response('%s', '%s', %s, '%s')" %
                        (response_obj.error.httpcode,
                        self.request.protocol + "://" + self.request.host + self.request.uri,
                        "'"+response_obj.jsonWrite().replace("'", "''")+"'",
                        #"'"+response_obj.jsonWrite()+"'",
                        remote_ip))

        return
