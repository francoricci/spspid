import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), "lib"))
sys.path.append(os.path.join(os.path.dirname(__file__), "modules"))

import socket
import tornado.ioloop
import tornado.web
import tornado.httpserver
import tornado.util
import tornado.netutil
import tornado.process
import logging.config
from concurrent.futures import ThreadPoolExecutor
import jsonpickle as jsonpickle
import re
import globalsObj
import commonlib
from tornado.platform.asyncio import AsyncIOMainLoop
import asyncio
from mutornadomon.config import initialize_mutornadomon
import signal
import configparser

"""
Load default logging file config
"""
path = os.path.dirname(os.path.realpath(__file__))
globalsObj.loggingConfig = commonlib.incrementalIniFile(globalsObj.CONFIG_LOGGING_PATH)
#globalsObj.loggingFile = globalsObj.CONFIG_LOGGING_PATH
logging.config.fileConfig(globalsObj.loggingConfig)

"""
read config file passed in command line and load core server wspath
"""
#write root location
globalsObj.rootFolder = path
globalsObj.cmdLineoOptions = commonlib.commandLine(globalsObj.CONFIG_FILE_PATH)
globalsObj.configuration = commonlib.configure(globalsObj.CONFIG_FILE_PATH)
globalsObj.ws_configuration = commonlib.configure(globalsObj.configuration.get('wspath','conf'))
globalsObj.errors_configuration = commonlib.configure(globalsObj.configuration.get('errors','conf'))
globalsObj.configuration = commonlib.configure(globalsObj.cmdLineoOptions.filename, globalsObj.configuration)
globalsObj.modules_configuration = dict()

if os.path.exists(os.path.join(globalsObj.rootFolder, globalsObj.configuration.get('Application','modules_dir'))):
    globalsObj.modules_basedir = os.path.join(globalsObj.rootFolder, globalsObj.configuration.get('Application','modules_dir'))
    sys.path.append(globalsObj.modules_basedir)
else:
    globalsObj.modules_basedir = globalsObj.configuration.get('Application','modules_dir')
    sys.path.append(globalsObj.modules_basedir)

if os.path.isfile(os.path.join(path, globalsObj.configuration.get('logging','conf'))):
    globalsObj.lastLoggingFile = os.path.join(path, globalsObj.configuration.get('logging','conf'))
else:
    globalsObj.lastLoggingFile = globalsObj.configuration.get('logging','conf')


"""
scan modules dir to load modules default configuration and logging files
"""
modules_to_import = list()
with os.scandir(globalsObj.modules_basedir) as it:
    for module in it:
        if not module.name.startswith('.') and not module.name.startswith('_') and module.is_dir():
            tmp  = {'from': module.name+'.handlers', 'import': list()}

            # logging
            try:
                fname = os.path.join(globalsObj.modules_basedir, module.name, 'conf', 'logging.ini')
                if os.path.isfile(fname):
                    globalsObj.loggingConfig = commonlib.incrementalIniFile(fname, globalsObj.loggingConfig)
            except Exception as exc:
                pass

            # conf
            try:
                fname = os.path.join(globalsObj.modules_basedir, module.name, 'conf', module.name+'.ini')
                if os.path.isfile(fname):
                    globalsObj.modules_configuration[module.name] = commonlib.configure(fname)

                if globalsObj.configuration.has_option(module.name,'conf'):
                    globalsObj.modules_configuration[module.name] = commonlib.configure(globalsObj.configuration.get(module.name,'conf'),
                                        globalsObj.modules_configuration[module.name])
            except Exception as exc:
                pass

            with os.scandir(os.path.join(module.path, 'handlers')) as it2:
                for module2 in it2:
                    if not module2.name.startswith('.') and not module2.name.startswith('_') and module2.is_file():
                        if module2.name.endswith('.pyc') and not module2.name[:-4] in tmp['import']:
                            tmp['import'].append(re.sub(r'\.pyc$', '', module2.name))
                        elif module2.name.endswith('.py') and not module2.name[:-3] in tmp['import']:
                            tmp['import'].append(re.sub(r'\.py$', '', module2.name))

            wspath_name = os.path.join(globalsObj.modules_basedir, module.name, 'conf', 'wspath.ini')
            if os.path.isfile(wspath_name):
                globalsObj.ws_configuration = commonlib.configure(wspath_name, globalsObj.ws_configuration)

            tmp['import'] = ', '.join(tmp['import'])
            modules_to_import.append(tmp)


"""
load last configuration
"""
globalsObj.ws_configuration = commonlib.configure(globalsObj.configuration.get('wspath','conf'), globalsObj.ws_configuration)
globalsObj.errors_configuration = commonlib.configure(globalsObj.configuration.get('errors','conf'), globalsObj.errors_configuration)

globalsObj.loggingConfig = commonlib.incrementalIniFile(globalsObj.lastLoggingFile, globalsObj.loggingConfig, overwrite = True)
logging.config.fileConfig(globalsObj.loggingConfig, disable_existing_loggers=False)

# install async loop
if globalsObj.configuration.getboolean('Application','libuv'):
    import uvloop
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())

AsyncIOMainLoop().install()
globalsObj.ioloop = asyncio.get_event_loop()

# set asyncio debug
if globalsObj.configuration.getboolean('Application','debug'):
    globalsObj.ioloop.set_debug('enabled')


"""
core handlers
"""
from handle import VersionHandler
from handle import MainHandler
from handle import StaticHandler

for module in modules_to_import:
    logging.getLogger(__name__).info("Loaded module %s.%s" % (module['from'], module['import']))
    exec("from %s import %s" % (module['from'], module['import']))

"""
load mudules error messages in globalObjects
"""
with os.scandir(globalsObj.modules_basedir) as it:
    for module in it:
        try:
            fname = os.path.join(globalsObj.modules_basedir, module.name, 'conf', 'errors.ini')
            if os.path.isfile(fname):
                module_error_configuration = commonlib.configure(fname)

            for i, val in enumerate(module_error_configuration.sections()):
                if val != 'conf':
                    try:
                        globalsObj.errors_configuration.add_section(val)
                        tempDict = dict(module_error_configuration.items(val))
                        for j, val2 in enumerate(tempDict.keys()):
                            globalsObj.errors_configuration.set(val, val2, tempDict[val2])
                    except configparser.DuplicateSectionError as error:
                        logging.getLogger(__name__).warning("Error loading " + module.name + " error messages: " + error.message )
        except Exception as exc:
            pass

class WebApp(tornado.web.Application):
    def __init__(self, configuration, ws_configuration_list):

        """ configure TCP server """
        try:
            """ Building URL """
            handlers = []
            for i, val in enumerate(ws_configuration_list.sections()):
                if val != 'conf':
                    tempDict = dict(ws_configuration_list.items(val))
                    temp = ""
                    for j, val2 in enumerate(tempDict.keys()):
                        temp += "%s=%s," % (val2,tempDict[val2])
                    temp = temp.strip(',')
                    urlTemp = "tornado.web.URLSpec(%s)" % (temp)
                    handlers.append(eval(urlTemp))
                    logging.getLogger(__name__).info("Created API. %s" % temp)

            """ create web application """
            super(self.__class__, self).__init__(handlers,
                    debug=configuration.getboolean('Application','debug'),
                    autoreload=configuration.getboolean('Application','autoreload'))
            self.executor = ThreadPoolExecutor(max_workers=configuration.getint('Application','max_workers'))

        #except tornado.web.ErrorHandler as error:
        except Exception as error:
            rootLogger.error("Tornado web error: %s" % (error))


def shut_down(*args):
    rootLogger.warning("Torando ioloop is stopping ....")
    if globalsObj.configuration.getboolean('Monitor','enable'):
        monitor.stop()
    globalsObj.ioloop.stop()
    rootLogger.warning("Torando stopped!")

if __name__ == '__main__':
    rootLogger = logging.getLogger(__name__)

    tcp_conf = dict(globalsObj.configuration.items('TCP'))
    # write pid file
    commonlib.writePid(globalsObj.configuration.get('pid','file'))

    # create app
    globalsObj.ws_configuration.read_dict(globalsObj.deniedPath)
    webapp = WebApp(globalsObj.configuration, globalsObj.ws_configuration)

    # initialize monitor
    if globalsObj.configuration.getboolean('Monitor','enable'):
        monitor = initialize_mutornadomon(webapp, request_filter=commonlib.match_host)

    for sig in (signal.SIGQUIT, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, shut_down)

    # set backend to serilize objects
    jsonpickle.set_preferred_backend('simplejson')
    jsonpickle.set_encoder_options('simplejson', ensure_ascii=True, indent=4)

    try:
        sockets = tornado.netutil.bind_sockets(tcp_conf['port'],tcp_conf['address'], family=socket.AF_INET, backlog = int(tcp_conf['backlog']),
                                               reuse_port=bool(tcp_conf['reuseport']))

        rootLogger.warning("Found %s processor/s" % (tornado.process.cpu_count()))
        if (tcp_conf['num_processes'] == '0'):
            rootLogger.warning("Starting %s process/es listening on address %s, port %s"
                     % (tornado.process.cpu_count(), tcp_conf['address'], tcp_conf['port']))
        else:
            rootLogger.warning("Starting %s process/es listening on address %s, port %s"
                     % (tcp_conf['num_processes'], tcp_conf['address'], tcp_conf['port']))

        server = tornado.httpserver.HTTPServer(webapp,
                xheaders=globalsObj.configuration.getboolean('HTTP','xheaders'),
                protocol=globalsObj.configuration.get('HTTP','protocol'))

        server.add_sockets(sockets)

        """ main loop """
        globalsObj.ioloop.set_default_executor(webapp.executor)
        globalsObj.ioloop.run_forever()

    except socket.error as error:
        rootLogger.error("error on server socket: %s" % (error))

    except Exception as exc:
        rootLogger.error("General error catch: %s" % (exc))
