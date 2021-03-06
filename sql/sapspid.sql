--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 9.6.3

-- Started on 2017-12-07 22:58:49 CET

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 10 (class 2615 OID 16396)
-- Name: jwt; Type: SCHEMA; Schema: -; Owner: easyspid
--

CREATE SCHEMA jwt;


ALTER SCHEMA jwt OWNER TO easyspid;

--
-- TOC entry 11 (class 2615 OID 16397)
-- Name: lib; Type: SCHEMA; Schema: -; Owner: easyspid
--

CREATE SCHEMA lib;


ALTER SCHEMA lib OWNER TO easyspid;

--
-- TOC entry 13 (class 2615 OID 18396)
-- Name: log; Type: SCHEMA; Schema: -; Owner: easyspid
--

CREATE SCHEMA log;


ALTER SCHEMA log OWNER TO easyspid;

--
-- TOC entry 12 (class 2615 OID 16398)
-- Name: saml; Type: SCHEMA; Schema: -; Owner: easyspid
--

CREATE SCHEMA saml;


ALTER SCHEMA saml OWNER TO easyspid;

--
-- TOC entry 2 (class 3079 OID 12744)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 2802 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- TOC entry 1 (class 3079 OID 16399)
-- Name: plpython3u; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpython3u WITH SCHEMA pg_catalog;


--
-- TOC entry 2803 (class 0 OID 0)
-- Dependencies: 1
-- Name: EXTENSION plpython3u; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpython3u IS 'PL/Python3U untrusted procedural language';


--
-- TOC entry 3 (class 3079 OID 16404)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 2804 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET search_path = jwt, pg_catalog;

--
-- TOC entry 260 (class 1255 OID 16415)
-- Name: header_validator(); Type: FUNCTION; Schema: jwt; Owner: easyspid
--

CREATE FUNCTION header_validator() RETURNS trigger
    LANGUAGE plpgsql
    AS $$  DECLARE
       json_valid text;
       json_schema jsonb;
    BEGIN
       SELECT t1.schema INTO json_schema FROM jwt.token_schemas as t1
       WHERE t1.cod_type = NEW.cod_type and t1.part = 'header' 
       and t1.active = True;

       SELECT lib.jsonvalidate(NEW.header, json_schema) INTO json_valid;
       
       IF json_valid = '0' THEN
            RETURN NEW;
       END IF;
        RAISE EXCEPTION '%s', json_valid;
        RETURN NEW;
    END;
$$;


ALTER FUNCTION jwt.header_validator() OWNER TO easyspid;

--
-- TOC entry 259 (class 1255 OID 16416)
-- Name: payload_validator(); Type: FUNCTION; Schema: jwt; Owner: easyspid
--

CREATE FUNCTION payload_validator() RETURNS trigger
    LANGUAGE plpgsql
    AS $$  DECLARE
       json_valid text;
       json_schema jsonb;
    BEGIN
       SELECT t1.schema INTO json_schema FROM jwt.token_schemas as t1
       WHERE t1.cod_type = NEW.cod_type and t1.part = 'payload' 
       and t1.active = True;

       SELECT lib.jsonvalidate(NEW.payload, json_schema) INTO json_valid;
       
       IF json_valid = '0' THEN
            RETURN NEW;
       END IF;
        RAISE EXCEPTION '%s', json_valid;
        RETURN NEW;
    END;
$$;


ALTER FUNCTION jwt.payload_validator() OWNER TO easyspid;

--
-- TOC entry 247 (class 1255 OID 16417)
-- Name: schemas_validator(); Type: FUNCTION; Schema: jwt; Owner: easyspid
--

CREATE FUNCTION schemas_validator() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
       json_valid_pl integer;
       json_valid_he integer;
       results integer;
    BEGIN
     SELECT SUM(lib.jsonvalidate(t1.payload, NEW.schema)::integer) INTO json_valid_pl 
     FROM jwt.token_payload as t1 WHERE NEW.cod_type = t1.cod_type AND NEW.part = 'payload';
     IF (json_valid_pl IS NULL OR json_valid_pl = 0) THEN
        results := json_valid_pl;
     ELSE
        RAISE EXCEPTION '%s', json_valid_he;
        RETURN NULL;
     END IF;
       
     SELECT SUM(lib.jsonvalidate(t1.header, NEW.schema)::integer) INTO json_valid_he 
     FROM jwt.token_signature as t1 WHERE NEW.cod_type = t1.cod_type and NEW.part = 'header';
     IF (json_valid_he IS NULL OR json_valid_he = 0) THEN
        results := json_valid_he;
     ELSE
        RAISE EXCEPTION '%s', json_valid_he;
        RETURN NULL;
     END IF;
     RETURN NEW;
    END;

$$;


ALTER FUNCTION jwt.schemas_validator() OWNER TO easyspid;

SET search_path = lib, pg_catalog;

--
-- TOC entry 246 (class 1255 OID 16418)
-- Name: config_token_bytype(character varying); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION config_token_bytype(incod_type character varying DEFAULT 'jwt1'::character varying) RETURNS character varying
    LANGUAGE plpgsql PARALLEL SAFE
    AS $$

  DECLARE
       newheader jsonb;
       newcod_token varchar;
       validity integer;
       newpaylod jsonb;
       newdate timestamp with time zone;
       newepoch double precision;
       new_token text;
  BEGIN
   SELECT CURRENT_TIMESTAMP(0) into newdate;
   SELECT extract(epoch from newdate at time zone 'UTC') into newepoch;
   select t1.header, t1.validity, t1.payload  INTO newheader, validity, newpaylod 
       from jwt.view_token_type as t1 where t1.cod_type = incod_type;
   select public.uuid_generate_v4()::varchar into newcod_token;
   
   SELECT jsonb_set(newpaylod, '{"iat"}',  newepoch::text::jsonb, true) into newpaylod;
   SELECT jsonb_set(newpaylod, '{"nbf"}',  newepoch::text::jsonb, true) into newpaylod;
   SELECT jsonb_set(newpaylod, '{"exp"}', (newepoch+validity)::text::jsonb, true) into newpaylod;
   SELECT jsonb_set(newpaylod, '{"jti"}', to_jsonb(newcod_token), true) into newpaylod;
   
   insert into jwt.token ("header", payload, cod_type, cod_token, "date") values (newheader, newpaylod, incod_type, newcod_token, newdate) returning cod_token into new_token;
   
   RETURN new_token;
  end;
  

$$;


ALTER FUNCTION lib.config_token_bytype(incod_type character varying) OWNER TO easyspid;

--
-- TOC entry 2805 (class 0 OID 0)
-- Dependencies: 246
-- Name: FUNCTION config_token_bytype(incod_type character varying); Type: COMMENT; Schema: lib; Owner: easyspid
--

COMMENT ON FUNCTION config_token_bytype(incod_type character varying) IS 'Configure header and payload parts of a new token and insert them into token table. Returns cod_token';


--
-- TOC entry 248 (class 1255 OID 16419)
-- Name: create_token_bytype(character varying); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION create_token_bytype(incod_type character varying DEFAULT 'jwt1'::character varying) RETURNS character varying
    LANGUAGE plpgsql PARALLEL SAFE
    AS $$

    
    DECLARE 
      newcod_token varchar;
      newtoken text;
      newpayload jsonb;
      newheader jsonb;
      newkey text;
      newalg varchar;
    BEGIN
    
    newcod_token := (SELECT lib.config_token_bytype(incod_type));
    SELECT t1.header, t1.payload, t1.header ->> 'alg', t1.key  INTO newheader, newpayload, newalg, newkey
        FROM jwt.view_token as t1 where t1.cod_token = newcod_token;
    
    newtoken := (SELECT lib.encode_token(newpayload::text, newkey, newalg, newheader::text)); 
    UPDATE jwt.token set "token" =  newtoken WHERE cod_token = newcod_token;
    
    RETURN newcod_token;
    END;
   

$$;


ALTER FUNCTION lib.create_token_bytype(incod_type character varying) OWNER TO easyspid;

--
-- TOC entry 249 (class 1255 OID 16420)
-- Name: encode_token(text, text, character varying, text); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION encode_token(payload text, secretkey text, algorithm character varying, headers text, OUT new_token text) RETURNS text
    LANGUAGE plpython3u IMMUTABLE STRICT PARALLEL SAFE
    AS $$

  import jwt
  import simplejson
  try:
      payl = simplejson.loads(payload)
      head = simplejson.loads(headers)
      token = jwt.encode(payl, secretkey, algorithm, head)
      new_token = token.decode("utf-8")
      return new_token
  except BaseException as error:
      return "error: %s" % (error)

$$;


ALTER FUNCTION lib.encode_token(payload text, secretkey text, algorithm character varying, headers text, OUT new_token text) OWNER TO easyspid;

--
-- TOC entry 2806 (class 0 OID 0)
-- Dependencies: 249
-- Name: FUNCTION encode_token(payload text, secretkey text, algorithm character varying, headers text, OUT new_token text); Type: COMMENT; Schema: lib; Owner: easyspid
--

COMMENT ON FUNCTION encode_token(payload text, secretkey text, algorithm character varying, headers text, OUT new_token text) IS 'Simple mapping of jwt.encode function';


--
-- TOC entry 250 (class 1255 OID 16421)
-- Name: encode_token_bycod(character varying); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION encode_token_bycod(cod character varying, OUT new_token text) RETURNS text
    LANGUAGE plpython3u STABLE STRICT PARALLEL SAFE
    AS $_$

  
import jwt
import simplejson
try:
 st = "SELECT t1.header, t1.payload, t1.header ->> 'alg' as algorithm, t1.key FROM jwt.view_token as t1 where t1.cod_token = $1"
 pst = plpy.prepare(st, ["varchar"])
 query = plpy.execute(pst, [cod])
    
 if query.nrows() > 0:
  token = jwt.encode(simplejson.loads(query[0]["payload"]), query[0]["key"], query[0]["algorithm"], simplejson.loads(query[0]["header"]))
  new_token = token.decode("utf-8")
  return new_token
 else:
  return 'error: No code_token found'

except BaseException as error:
      return "error: %s" % (error)

$_$;


ALTER FUNCTION lib.encode_token_bycod(cod character varying, OUT new_token text) OWNER TO easyspid;

--
-- TOC entry 257 (class 1255 OID 18395)
-- Name: get_current_timestamp(); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION get_current_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
NEW.date = now();
RETURN NEW;
END;

$$;


ALTER FUNCTION lib.get_current_timestamp() OWNER TO easyspid;

--
-- TOC entry 258 (class 1255 OID 19148)
-- Name: getx509cert(xml); Type: FUNCTION; Schema: lib; Owner: root
--

CREATE FUNCTION getx509cert(xmldata xml) RETURNS text
    LANGUAGE plpython3u IMMUTABLE STRICT
    AS $$

from lxml import etree

"""
Get x509 cert of a saml assertion

:param xmlData: The element we should validate
:type: string | Document

"""
if xmldata is None or xmldata == '':
    return 'Empty string supplied as input'

parsedXml = etree.fromstring(xmldata)
cert_nodes = parsedXml.xpath(".//*[local-name()='KeyDescriptor'][@use='signing']//*[local-name()='X509Certificate']")

if len(cert_nodes) > 0:
    x509_cert = cert_nodes[0].text.replace('\x0D', '')
    x509_cert = x509_cert.replace('\r', '')
    x509_cert = x509_cert.replace('\n', '')
    tmp = ("-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----" % x509_cert)
    return  tmp

else:
    return 'Could not validate metadata signature: No signature nodes found.'

$$;


ALTER FUNCTION lib.getx509cert(xmldata xml) OWNER TO root;

--
-- TOC entry 251 (class 1255 OID 16422)
-- Name: jsonvalidate(jsonb, jsonb); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION jsonvalidate(jsonobj jsonb, jschema jsonb) RETURNS text
    LANGUAGE plpython3u IMMUTABLE STRICT PARALLEL SAFE
    AS $$
  from jsonschema import validate
  from jsonschema import exceptions
  import simplejson as json
  try:
      pyobj = json.loads(jsonobj)
      pyschema = json.loads(jschema)
      validate(pyobj, pyschema)
      return '0'
  except exceptions.ValidationError as error:
  #except BaseException, error:
      return "Validation error: %s\n%s" % (error.message, error.schema)
$$;


ALTER FUNCTION lib.jsonvalidate(jsonobj jsonb, jschema jsonb) OWNER TO easyspid;

--
-- TOC entry 252 (class 1255 OID 16423)
-- Name: verify_token(text, text, character varying, character varying, character varying, boolean); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION verify_token(intoken text, secretkey text, alg character varying, aud character varying, iss character varying, inverify boolean DEFAULT true, OUT new_token jsonb) RETURNS jsonb
    LANGUAGE plpython3u IMMUTABLE STRICT PARALLEL SAFE
    AS $$

  import jwt
  import simplejson
  try:
      token_jose = jwt.decode(intoken, secretkey, algorithms=alg, audience=aud, issuer=iss, verify=inverify)
      ##new_token = simplejson.dumps(token_jose)
      return simplejson.dumps({'error':0 ,'message': "%s" % (token_jose)})
      
  except jwt.exceptions.InvalidTokenError as error:
      return simplejson.dumps({'error':1 ,'message': "%s" % (error)})

$$;


ALTER FUNCTION lib.verify_token(intoken text, secretkey text, alg character varying, aud character varying, iss character varying, inverify boolean, OUT new_token jsonb) OWNER TO easyspid;

--
-- TOC entry 2807 (class 0 OID 0)
-- Dependencies: 252
-- Name: FUNCTION verify_token(intoken text, secretkey text, alg character varying, aud character varying, iss character varying, inverify boolean, OUT new_token jsonb); Type: COMMENT; Schema: lib; Owner: easyspid
--

COMMENT ON FUNCTION verify_token(intoken text, secretkey text, alg character varying, aud character varying, iss character varying, inverify boolean, OUT new_token jsonb) IS 'Simple mapping of jwt.decode function';


--
-- TOC entry 254 (class 1255 OID 16424)
-- Name: verify_token_bycod(character varying, boolean); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION verify_token_bycod(cod character varying, inverify boolean DEFAULT true, OUT new_token jsonb) RETURNS jsonb
    LANGUAGE plpython3u IMMUTABLE STRICT PARALLEL SAFE
    AS $_$

import jwt
import simplejson

try:
 st = "SELECT t1.token, t1.pubkey, t1.header->>'alg' as alg, t1.payload ->> 'aud' as aud, t1.payload ->> 'iss' as iss, t1.cod_token FROM jwt.view_token as t1 WHERE t1.cod_token = $1"
 pst = plpy.prepare(st, ["varchar"])
 query = plpy.execute(pst, [cod])
    
 if query.nrows() > 0:
  token_jose = jwt.decode(query[0]["token"], query[0]["pubkey"], algorithms=query[0]["alg"], audience=query[0]["aud"], issuer=query[0]["iss"], verify=inverify)
  #new_token = simplejson.dumps(token_jose)
  if token_jose['jti'] == query[0]["cod_token"]:
   return simplejson.dumps({'error':0 ,'message': "%s" % (token_jose)})
  else:
   return simplejson.dumps({'error':3, 'message':'jti value does not match cod_token'})
 else:
  return simplejson.dumps({'error':2, 'message':'code_token not found'})

except jwt.exceptions.InvalidTokenError as error:
    return simplejson.dumps({'error':1 ,'message': "%s" % (error)})

$_$;


ALTER FUNCTION lib.verify_token_bycod(cod character varying, inverify boolean, OUT new_token jsonb) OWNER TO easyspid;

--
-- TOC entry 255 (class 1255 OID 16425)
-- Name: x509_fingerprint(text, character varying); Type: FUNCTION; Schema: lib; Owner: easyspid
--

CREATE FUNCTION x509_fingerprint(x509cert text, alg character varying DEFAULT 'sha1'::character varying) RETURNS character varying
    LANGUAGE plpython3u IMMUTABLE STRICT
    AS $$
    from hashlib import sha1, sha256, sha384, sha512
    import base64
    
    try:
        lines = x509cert.split('\n')
        data = ''
    
        for line in lines:
            # Remove '\r' from end of line if present.
            line = line.rstrip()
            if line == '-----BEGIN CERTIFICATE-----':
                # Delete junk from before the certificate.
                data = ''
            elif line == '-----END CERTIFICATE-----':
                # Ignore data after the certificate.
                break
            elif line == '-----BEGIN PUBLIC KEY-----' or line == '-----BEGIN RSA PRIVATE KEY-----':
                # This isn't an X509 certificate.
                return  ""
            else:
                # Append the current line to the certificate data.
                data += line
    
        decoded_data = base64.b64decode(str(data))
    
        if alg == 'sha512':
            fingerprint = sha512(decoded_data)
        elif alg == 'sha384':
            fingerprint = sha384(decoded_data)
        elif alg == 'sha256':
            fingerprint = sha256(decoded_data)
        elif alg == None or alg == 'sha1':
            fingerprint = sha1(decoded_data)
        else:
            return ""
	    
        return fingerprint.hexdigest().lower()
    except BaseException as error:
        return error
       
    return ""
    
$$;


ALTER FUNCTION lib.x509_fingerprint(x509cert text, alg character varying) OWNER TO easyspid;

SET search_path = saml, pg_catalog;

--
-- TOC entry 256 (class 1255 OID 16426)
-- Name: assertions(); Type: FUNCTION; Schema: saml; Owner: easyspid
--

CREATE FUNCTION assertions() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE 
     id_xml xml[];
     id_response xml[];
     ass_type xml[];
     newcod_token varchar;
     new_type_token varchar;
BEGIN
	
	id_xml = xpath('/*/@ID', NEW."assertion");
	id_response = xpath('/*/@InResponseTo', NEW."assertion");
	ass_type = xpath('name(/*)', NEW."assertion");
	--newcod_token := (SELECT lib.create_token_bytype('jwt2'));

	IF coalesce(array_upper(ass_type, 1), 0) > 0 THEN
		--UPDATE saml.assertions SET ID_assertion = xmlserialize(CONTENT id_xml[1] as character varying), 
		--cod_type[1] = xmlserialize(CONTENT ass_type as character varying) WHERE "ID" = NEW."ID";
		--UPDATE saml.assertions SET "ID_assertion" = xmlserialize(CONTENT id_xml[1] as character varying) WHERE "ID" = NEW."ID";
		NEW."cod_type" = substring(xmlserialize(CONTENT ass_type[1] as character varying) from '[^:]+$');
		NEW."ID_assertion" = xmlserialize(CONTENT id_xml[1] as character varying);
		NEW."ID_response_assertion" = xmlserialize(CONTENT id_response[1] as character varying);
		SELECT t1.cod_type_token INTO new_type_token FROM saml.jwt_settings as t1 
				WHERE t1.cod_provider = NEW.cod_sp and t1.cod_type_assertion = NEW."cod_type";
		newcod_token := (SELECT lib.create_token_bytype(new_type_token));
		NEW."cod_token" = newcod_token;
	END IF;

	RETURN NEW;
END;
$_$;


ALTER FUNCTION saml.assertions() OWNER TO easyspid;

--
-- TOC entry 253 (class 1255 OID 16428)
-- Name: get_x509_fingerprint(); Type: FUNCTION; Schema: saml; Owner: easyspid
--

CREATE FUNCTION get_x509_fingerprint() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
NEW.fingerprint = lib.x509_fingerprint(NEW.public_key, NEW.fingerprintalg);
RETURN NEW;
END;
$$;


ALTER FUNCTION saml.get_x509_fingerprint() OWNER TO easyspid;

--
-- TOC entry 261 (class 1255 OID 19149)
-- Name: getx509cert(); Type: FUNCTION; Schema: saml; Owner: root
--

CREATE FUNCTION getx509cert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE 
     codCert varchar;
     certx509 text;
BEGIN

	SELECT INTO certx509 lib.getx509Cert(NEW.xml);
	SELECT cod_cert INTO codCert FROM saml.signatures WHERE cod_provider = NEW.cod_provider;
    
    IF codCert is NULL THEN
        INSERT INTO saml.signatures (cod_cert, cod_provider, public_key) VALUES ('cert_'||NEW.cod_provider, NEW.cod_provider, certx509);
    END IF;

    IF codCert is NOT NULL THEN
        UPDATE saml.signatures SET public_key = certx509 WHERE cod_cert = codCert AND public_key IS NULL;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION saml.getx509cert() OWNER TO root;

SET search_path = jwt, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 191 (class 1259 OID 16429)
-- Name: token; Type: TABLE; Schema: jwt; Owner: easyspid
--

CREATE TABLE token (
    cod_token character varying(255) DEFAULT public.uuid_generate_v4() NOT NULL,
    header jsonb NOT NULL,
    payload jsonb NOT NULL,
    token text,
    "ID" integer NOT NULL,
    cod_type character varying(50) DEFAULT 'jwt1'::character varying NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE token OWNER TO easyspid;

--
-- TOC entry 192 (class 1259 OID 16438)
-- Name: token_ID_seq; Type: SEQUENCE; Schema: jwt; Owner: easyspid
--

CREATE SEQUENCE "token_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "token_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2808 (class 0 OID 0)
-- Dependencies: 192
-- Name: token_ID_seq; Type: SEQUENCE OWNED BY; Schema: jwt; Owner: easyspid
--

ALTER SEQUENCE "token_ID_seq" OWNED BY token."ID";


--
-- TOC entry 193 (class 1259 OID 16440)
-- Name: token_payload; Type: TABLE; Schema: jwt; Owner: easyspid
--

CREATE TABLE token_payload (
    "ID" integer NOT NULL,
    cod_payload character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    cod_type character varying(50) DEFAULT 'jwt1'::character varying NOT NULL,
    payload jsonb DEFAULT '{"aud": "Service Provider", "exp": 1, "iat": 1, "iss": "EasySPID", "nbf": 1, "sub": "saml assertion validator"}'::jsonb NOT NULL
);


ALTER TABLE token_payload OWNER TO easyspid;

--
-- TOC entry 194 (class 1259 OID 16449)
-- Name: token_payload_ID_seq; Type: SEQUENCE; Schema: jwt; Owner: easyspid
--

CREATE SEQUENCE "token_payload_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "token_payload_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2809 (class 0 OID 0)
-- Dependencies: 194
-- Name: token_payload_ID_seq; Type: SEQUENCE OWNED BY; Schema: jwt; Owner: easyspid
--

ALTER SEQUENCE "token_payload_ID_seq" OWNED BY token_payload."ID";


--
-- TOC entry 195 (class 1259 OID 16451)
-- Name: token_schemas; Type: TABLE; Schema: jwt; Owner: easyspid
--

CREATE TABLE token_schemas (
    "ID" integer NOT NULL,
    cod_schema character varying(255) DEFAULT public.uuid_generate_v4() NOT NULL,
    schema jsonb NOT NULL,
    active boolean DEFAULT true NOT NULL,
    note text,
    cod_type character varying(50) DEFAULT 'jwt1'::character varying NOT NULL,
    part character varying(50),
    CONSTRAINT token_schemas_part_check CHECK ((((part)::text = 'header'::text) OR ((part)::text = 'payload'::text)))
);


ALTER TABLE token_schemas OWNER TO easyspid;

--
-- TOC entry 196 (class 1259 OID 16461)
-- Name: token_schemas_ID_seq; Type: SEQUENCE; Schema: jwt; Owner: easyspid
--

CREATE SEQUENCE "token_schemas_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "token_schemas_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2810 (class 0 OID 0)
-- Dependencies: 196
-- Name: token_schemas_ID_seq; Type: SEQUENCE OWNED BY; Schema: jwt; Owner: easyspid
--

ALTER SEQUENCE "token_schemas_ID_seq" OWNED BY token_schemas."ID";


--
-- TOC entry 197 (class 1259 OID 16463)
-- Name: token_signature; Type: TABLE; Schema: jwt; Owner: easyspid
--

CREATE TABLE token_signature (
    "ID" integer NOT NULL,
    cod_signature character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    key text DEFAULT 'bellapetutti'::text NOT NULL,
    cod_type character varying(50) DEFAULT 'jwt1'::character varying NOT NULL,
    validity integer DEFAULT 1200 NOT NULL,
    header jsonb DEFAULT '{"alg": "HS256", "typ": "JWT"}'::jsonb NOT NULL,
    pubkey text
);


ALTER TABLE token_signature OWNER TO easyspid;

--
-- TOC entry 198 (class 1259 OID 16474)
-- Name: token_signature_ID_seq; Type: SEQUENCE; Schema: jwt; Owner: easyspid
--

CREATE SEQUENCE "token_signature_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "token_signature_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2811 (class 0 OID 0)
-- Dependencies: 198
-- Name: token_signature_ID_seq; Type: SEQUENCE OWNED BY; Schema: jwt; Owner: easyspid
--

ALTER SEQUENCE "token_signature_ID_seq" OWNED BY token_signature."ID";


--
-- TOC entry 199 (class 1259 OID 16476)
-- Name: token_type; Type: TABLE; Schema: jwt; Owner: easyspid
--

CREATE TABLE token_type (
    "ID" integer NOT NULL,
    cod_type character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    note text
);


ALTER TABLE token_type OWNER TO easyspid;

--
-- TOC entry 200 (class 1259 OID 16483)
-- Name: token_type_ID_seq; Type: SEQUENCE; Schema: jwt; Owner: easyspid
--

CREATE SEQUENCE "token_type_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "token_type_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2812 (class 0 OID 0)
-- Dependencies: 200
-- Name: token_type_ID_seq; Type: SEQUENCE OWNED BY; Schema: jwt; Owner: easyspid
--

ALTER SEQUENCE "token_type_ID_seq" OWNED BY token_type."ID";


--
-- TOC entry 201 (class 1259 OID 16485)
-- Name: view_token; Type: VIEW; Schema: jwt; Owner: easyspid
--

CREATE VIEW view_token AS
 SELECT t1.cod_token,
    t1.header,
    t1.payload,
    t1.token,
    t1."ID",
    t1.cod_type,
    t1.date,
    t2.key,
    t2.pubkey,
    t2.validity
   FROM (token t1
     LEFT JOIN token_signature t2 ON (((t2.cod_type)::text = (t1.cod_type)::text)));


ALTER TABLE view_token OWNER TO easyspid;

--
-- TOC entry 202 (class 1259 OID 16489)
-- Name: view_token_type; Type: VIEW; Schema: jwt; Owner: easyspid
--

CREATE VIEW view_token_type AS
 SELECT t1."ID",
    t1.cod_type,
    t1.note,
    t2.header,
    t2.validity,
    t2.key,
    t2.pubkey,
    t3.payload
   FROM ((token_type t1
     LEFT JOIN token_signature t2 ON (((t2.cod_type)::text = (t1.cod_type)::text)))
     LEFT JOIN token_payload t3 ON (((t3.cod_type)::text = (t1.cod_type)::text)));


ALTER TABLE view_token_type OWNER TO easyspid;

SET search_path = log, pg_catalog;

--
-- TOC entry 220 (class 1259 OID 18397)
-- Name: requests; Type: TABLE; Schema: log; Owner: easyspid
--

CREATE TABLE requests (
    "ID" integer NOT NULL,
    cod_request character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    http_verb character varying(50) NOT NULL,
    url text NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL,
    client inet NOT NULL,
    request text
);


ALTER TABLE requests OWNER TO easyspid;

--
-- TOC entry 221 (class 1259 OID 18405)
-- Name: request_ID_seq; Type: SEQUENCE; Schema: log; Owner: easyspid
--

CREATE SEQUENCE "request_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "request_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2813 (class 0 OID 0)
-- Dependencies: 221
-- Name: request_ID_seq; Type: SEQUENCE OWNED BY; Schema: log; Owner: easyspid
--

ALTER SEQUENCE "request_ID_seq" OWNED BY requests."ID";


--
-- TOC entry 222 (class 1259 OID 18407)
-- Name: responses; Type: TABLE; Schema: log; Owner: easyspid
--

CREATE TABLE responses (
    "ID" integer NOT NULL,
    cod_response character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    http_code character varying(50) NOT NULL,
    url_origin text NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL,
    client inet NOT NULL,
    response text
);


ALTER TABLE responses OWNER TO easyspid;

--
-- TOC entry 223 (class 1259 OID 18415)
-- Name: respones_ID_seq; Type: SEQUENCE; Schema: log; Owner: easyspid
--

CREATE SEQUENCE "respones_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "respones_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2814 (class 0 OID 0)
-- Dependencies: 223
-- Name: respones_ID_seq; Type: SEQUENCE OWNED BY; Schema: log; Owner: easyspid
--

ALTER SEQUENCE "respones_ID_seq" OWNED BY responses."ID";


SET search_path = saml, pg_catalog;

--
-- TOC entry 203 (class 1259 OID 16493)
-- Name: assertions; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE assertions (
    "ID" integer NOT NULL,
    cod_assertion character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    assertion xml NOT NULL,
    cod_token character varying(50) NOT NULL,
    cod_type character varying(50) NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL,
    "ID_assertion" character varying(200),
    cod_sp character varying,
    cod_idp character varying,
    client inet,
    "ID_response_assertion" character varying(200)
);


ALTER TABLE assertions OWNER TO easyspid;

--
-- TOC entry 204 (class 1259 OID 16501)
-- Name: assertions_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "assertions_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "assertions_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2815 (class 0 OID 0)
-- Dependencies: 204
-- Name: assertions_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "assertions_ID_seq" OWNED BY assertions."ID";


--
-- TOC entry 205 (class 1259 OID 16503)
-- Name: assertions_type; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE assertions_type (
    "ID" integer NOT NULL,
    cod_type character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    type character varying(255) NOT NULL
);


ALTER TABLE assertions_type OWNER TO easyspid;

--
-- TOC entry 206 (class 1259 OID 16507)
-- Name: assertions_type_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "assertions_type_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "assertions_type_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2816 (class 0 OID 0)
-- Dependencies: 206
-- Name: assertions_type_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "assertions_type_ID_seq" OWNED BY assertions_type."ID";


--
-- TOC entry 207 (class 1259 OID 16509)
-- Name: signatures; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE signatures (
    "ID" integer NOT NULL,
    cod_cert character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    private_key text,
    public_key text NOT NULL,
    cod_provider character varying(50) NOT NULL,
    date timestamp with time zone DEFAULT now() NOT NULL,
    fingerprint text NOT NULL,
    fingerprintalg character varying(50) DEFAULT 'sha1'::character varying NOT NULL,
    CONSTRAINT signatures_fingerprintalg_check CHECK (((fingerprintalg)::text = ANY (ARRAY[('sha1'::character varying)::text, ('sha256'::character varying)::text, ('sha384'::character varying)::text, ('sha512'::character varying)::text])))
);


ALTER TABLE signatures OWNER TO easyspid;

--
-- TOC entry 2817 (class 0 OID 0)
-- Dependencies: 207
-- Name: COLUMN signatures.private_key; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON COLUMN signatures.private_key IS 'x509 public key';


--
-- TOC entry 2818 (class 0 OID 0)
-- Dependencies: 207
-- Name: COLUMN signatures.public_key; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON COLUMN signatures.public_key IS 'x509 PEM encoded certificate';


--
-- TOC entry 2819 (class 0 OID 0)
-- Dependencies: 207
-- Name: COLUMN signatures.fingerprint; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON COLUMN signatures.fingerprint IS 'base64 encoded x509 certificate hash';


--
-- TOC entry 2820 (class 0 OID 0)
-- Dependencies: 207
-- Name: COLUMN signatures.fingerprintalg; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON COLUMN signatures.fingerprintalg IS 'algorithm to use in fingerprint hashing';


--
-- TOC entry 208 (class 1259 OID 16519)
-- Name: certifcates_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "certifcates_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "certifcates_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2821 (class 0 OID 0)
-- Dependencies: 208
-- Name: certifcates_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "certifcates_ID_seq" OWNED BY signatures."ID";


--
-- TOC entry 209 (class 1259 OID 16521)
-- Name: jwt_settings; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE jwt_settings (
    "ID" integer NOT NULL,
    cod_jwt_setting character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    cod_provider character varying(50) NOT NULL,
    cod_type_assertion character varying(50) NOT NULL,
    cod_type_token character varying(50)
);


ALTER TABLE jwt_settings OWNER TO easyspid;

--
-- TOC entry 210 (class 1259 OID 16525)
-- Name: jwt_settings_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "jwt_settings_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "jwt_settings_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2822 (class 0 OID 0)
-- Dependencies: 210
-- Name: jwt_settings_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "jwt_settings_ID_seq" OWNED BY jwt_settings."ID";


--
-- TOC entry 211 (class 1259 OID 16527)
-- Name: metadata; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE metadata (
    "ID" integer NOT NULL,
    cod_metadata character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    xml xml,
    date timestamp with time zone DEFAULT now() NOT NULL,
    note text,
    active boolean DEFAULT true NOT NULL,
    cod_provider character varying(50) NOT NULL,
    CONSTRAINT metadata_active_check CHECK (((active = true) OR (active = false)))
);


ALTER TABLE metadata OWNER TO easyspid;

--
-- TOC entry 2823 (class 0 OID 0)
-- Dependencies: 211
-- Name: TABLE metadata; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON TABLE metadata IS 'Put here Identity Providers Metadata';


--
-- TOC entry 212 (class 1259 OID 16537)
-- Name: metadata_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "metadata_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "metadata_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2824 (class 0 OID 0)
-- Dependencies: 212
-- Name: metadata_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "metadata_ID_seq" OWNED BY metadata."ID";


--
-- TOC entry 213 (class 1259 OID 16539)
-- Name: providers; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE providers (
    "ID" integer NOT NULL,
    cod_provider character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    type character varying(255) DEFAULT 'idp'::character varying NOT NULL,
    description text,
    active boolean DEFAULT true NOT NULL,
    date timestamp with time zone DEFAULT now(),
    name character varying(255) NOT NULL,
    CONSTRAINT providers_active_check CHECK (((active = true) OR (active = false))),
    CONSTRAINT providers_type_check CHECK ((((type)::text = 'idp'::text) OR ((type)::text = 'sp'::text) OR ((type)::text = 'gw'::text)))
);


ALTER TABLE providers OWNER TO easyspid;

--
-- TOC entry 214 (class 1259 OID 16551)
-- Name: providers_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "providers_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "providers_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2825 (class 0 OID 0)
-- Dependencies: 214
-- Name: providers_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "providers_ID_seq" OWNED BY providers."ID";


--
-- TOC entry 215 (class 1259 OID 16553)
-- Name: services; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE services (
    "ID" integer NOT NULL,
    cod_service character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    relay_state text NOT NULL,
    description text,
    cod_provider character varying(50) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    url character varying(255) NOT NULL,
    CONSTRAINT services_active_check CHECK (((active = true) OR (active = false)))
);


ALTER TABLE services OWNER TO easyspid;

--
-- TOC entry 2826 (class 0 OID 0)
-- Dependencies: 215
-- Name: TABLE services; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON TABLE services IS 'Services requestd by user to service provider';


--
-- TOC entry 216 (class 1259 OID 16562)
-- Name: services_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "services_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "services_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2827 (class 0 OID 0)
-- Dependencies: 216
-- Name: services_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "services_ID_seq" OWNED BY services."ID";


--
-- TOC entry 217 (class 1259 OID 16564)
-- Name: settings; Type: TABLE; Schema: saml; Owner: easyspid
--

CREATE TABLE settings (
    "ID" integer NOT NULL,
    cod_setting character varying(50) DEFAULT public.uuid_generate_v4() NOT NULL,
    active boolean DEFAULT false NOT NULL,
    cod_provider character varying(50) NOT NULL,
    settings jsonb,
    advanced_settings jsonb,
    date timestamp with time zone DEFAULT now() NOT NULL,
    note text
);


ALTER TABLE settings OWNER TO easyspid;

--
-- TOC entry 2828 (class 0 OID 0)
-- Dependencies: 217
-- Name: TABLE settings; Type: COMMENT; Schema: saml; Owner: easyspid
--

COMMENT ON TABLE settings IS 'Service Providers settings';


--
-- TOC entry 218 (class 1259 OID 16574)
-- Name: settings_ID_seq; Type: SEQUENCE; Schema: saml; Owner: easyspid
--

CREATE SEQUENCE "settings_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "settings_ID_seq" OWNER TO easyspid;

--
-- TOC entry 2829 (class 0 OID 0)
-- Dependencies: 218
-- Name: settings_ID_seq; Type: SEQUENCE OWNED BY; Schema: saml; Owner: easyspid
--

ALTER SEQUENCE "settings_ID_seq" OWNED BY settings."ID";


--
-- TOC entry 219 (class 1259 OID 16576)
-- Name: view_assertions; Type: VIEW; Schema: saml; Owner: easyspid
--

CREATE VIEW view_assertions AS
 SELECT t1."ID",
    t1.cod_assertion,
    t1.assertion,
    t1.cod_token,
    t2.cod_type AS cod_type_token,
    t2.token,
    t1.cod_type,
    t1.date,
    t1."ID_assertion",
    t1."ID_response_assertion",
    t1.cod_sp,
    t1.cod_idp,
    t1.client
   FROM (assertions t1
     LEFT JOIN jwt.token t2 ON (((t2.cod_token)::text = (t1.cod_token)::text)));


ALTER TABLE view_assertions OWNER TO easyspid;

SET search_path = jwt, pg_catalog;

--
-- TOC entry 2501 (class 2604 OID 16580)
-- Name: token ID; Type: DEFAULT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token ALTER COLUMN "ID" SET DEFAULT nextval('"token_ID_seq"'::regclass);


--
-- TOC entry 2505 (class 2604 OID 16581)
-- Name: token_payload ID; Type: DEFAULT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_payload ALTER COLUMN "ID" SET DEFAULT nextval('"token_payload_ID_seq"'::regclass);


--
-- TOC entry 2509 (class 2604 OID 16582)
-- Name: token_schemas ID; Type: DEFAULT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_schemas ALTER COLUMN "ID" SET DEFAULT nextval('"token_schemas_ID_seq"'::regclass);


--
-- TOC entry 2516 (class 2604 OID 16583)
-- Name: token_signature ID; Type: DEFAULT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_signature ALTER COLUMN "ID" SET DEFAULT nextval('"token_signature_ID_seq"'::regclass);


--
-- TOC entry 2518 (class 2604 OID 16584)
-- Name: token_type ID; Type: DEFAULT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_type ALTER COLUMN "ID" SET DEFAULT nextval('"token_type_ID_seq"'::regclass);


SET search_path = log, pg_catalog;

--
-- TOC entry 2553 (class 2604 OID 18417)
-- Name: requests ID; Type: DEFAULT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY requests ALTER COLUMN "ID" SET DEFAULT nextval('"request_ID_seq"'::regclass);


--
-- TOC entry 2556 (class 2604 OID 18418)
-- Name: responses ID; Type: DEFAULT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY responses ALTER COLUMN "ID" SET DEFAULT nextval('"respones_ID_seq"'::regclass);


SET search_path = saml, pg_catalog;

--
-- TOC entry 2521 (class 2604 OID 16585)
-- Name: assertions ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions ALTER COLUMN "ID" SET DEFAULT nextval('"assertions_ID_seq"'::regclass);


--
-- TOC entry 2523 (class 2604 OID 16586)
-- Name: assertions_type ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions_type ALTER COLUMN "ID" SET DEFAULT nextval('"assertions_type_ID_seq"'::regclass);


--
-- TOC entry 2530 (class 2604 OID 16587)
-- Name: jwt_settings ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings ALTER COLUMN "ID" SET DEFAULT nextval('"jwt_settings_ID_seq"'::regclass);


--
-- TOC entry 2534 (class 2604 OID 16588)
-- Name: metadata ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY metadata ALTER COLUMN "ID" SET DEFAULT nextval('"metadata_ID_seq"'::regclass);


--
-- TOC entry 2540 (class 2604 OID 16589)
-- Name: providers ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY providers ALTER COLUMN "ID" SET DEFAULT nextval('"providers_ID_seq"'::regclass);


--
-- TOC entry 2545 (class 2604 OID 16590)
-- Name: services ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY services ALTER COLUMN "ID" SET DEFAULT nextval('"services_ID_seq"'::regclass);


--
-- TOC entry 2549 (class 2604 OID 16591)
-- Name: settings ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY settings ALTER COLUMN "ID" SET DEFAULT nextval('"settings_ID_seq"'::regclass);


--
-- TOC entry 2527 (class 2604 OID 16592)
-- Name: signatures ID; Type: DEFAULT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY signatures ALTER COLUMN "ID" SET DEFAULT nextval('"certifcates_ID_seq"'::regclass);


SET search_path = jwt, pg_catalog;

--
-- TOC entry 2559 (class 2606 OID 16614)
-- Name: token token_cod_key; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token
    ADD CONSTRAINT token_cod_key UNIQUE (cod_token);


--
-- TOC entry 2566 (class 2606 OID 16616)
-- Name: token_payload token_payload_cod_payload_key; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_payload
    ADD CONSTRAINT token_payload_cod_payload_key UNIQUE (cod_payload);


--
-- TOC entry 2568 (class 2606 OID 16618)
-- Name: token_payload token_payload_pkey; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_payload
    ADD CONSTRAINT token_payload_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2563 (class 2606 OID 16620)
-- Name: token token_pkey; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token
    ADD CONSTRAINT token_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2571 (class 2606 OID 16622)
-- Name: token_schemas token_schemas_cod_schema_key; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_schemas
    ADD CONSTRAINT token_schemas_cod_schema_key UNIQUE (cod_schema);


--
-- TOC entry 2573 (class 2606 OID 16624)
-- Name: token_schemas token_schemas_pkey; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_schemas
    ADD CONSTRAINT token_schemas_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2577 (class 2606 OID 16626)
-- Name: token_signature token_signature_cod_signature_key; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_signature
    ADD CONSTRAINT token_signature_cod_signature_key UNIQUE (cod_signature);


--
-- TOC entry 2579 (class 2606 OID 16628)
-- Name: token_signature token_signature_pkey; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_signature
    ADD CONSTRAINT token_signature_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2581 (class 2606 OID 16630)
-- Name: token_type token_type_pk; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_type
    ADD CONSTRAINT token_type_pk PRIMARY KEY ("ID");


--
-- TOC entry 2583 (class 2606 OID 16632)
-- Name: token_type token_type_un; Type: CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_type
    ADD CONSTRAINT token_type_un UNIQUE (cod_type);


SET search_path = log, pg_catalog;

--
-- TOC entry 2633 (class 2606 OID 18423)
-- Name: requests request_cod_request_key; Type: CONSTRAINT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY requests
    ADD CONSTRAINT request_cod_request_key UNIQUE (cod_request);


--
-- TOC entry 2635 (class 2606 OID 18425)
-- Name: requests request_pkey; Type: CONSTRAINT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY requests
    ADD CONSTRAINT request_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2637 (class 2606 OID 18427)
-- Name: responses response_cod_response_key; Type: CONSTRAINT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY responses
    ADD CONSTRAINT response_cod_response_key UNIQUE (cod_response);


--
-- TOC entry 2639 (class 2606 OID 18429)
-- Name: responses response_pkey; Type: CONSTRAINT; Schema: log; Owner: easyspid
--

ALTER TABLE ONLY responses
    ADD CONSTRAINT response_pkey PRIMARY KEY ("ID");


SET search_path = saml, pg_catalog;

--
-- TOC entry 2586 (class 2606 OID 16636)
-- Name: assertions assertions_cod_assertion_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_cod_assertion_key UNIQUE (cod_assertion);


--
-- TOC entry 2588 (class 2606 OID 16638)
-- Name: assertions assertions_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2590 (class 2606 OID 16640)
-- Name: assertions_type assertions_type_cod_type_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions_type
    ADD CONSTRAINT assertions_type_cod_type_key UNIQUE (cod_type);


--
-- TOC entry 2592 (class 2606 OID 16642)
-- Name: assertions_type assertions_type_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions_type
    ADD CONSTRAINT assertions_type_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2594 (class 2606 OID 16644)
-- Name: signatures certifcates_cod_cert_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY signatures
    ADD CONSTRAINT certifcates_cod_cert_key UNIQUE (cod_cert);


--
-- TOC entry 2596 (class 2606 OID 16646)
-- Name: signatures certifcates_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY signatures
    ADD CONSTRAINT certifcates_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2599 (class 2606 OID 16648)
-- Name: jwt_settings jwt_settings_cod_jwt_setting_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_cod_jwt_setting_key UNIQUE (cod_jwt_setting);


--
-- TOC entry 2601 (class 2606 OID 21556)
-- Name: jwt_settings jwt_settings_cod_provider_cod_type_assertion_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_cod_provider_cod_type_assertion_key UNIQUE (cod_provider, cod_type_assertion);


--
-- TOC entry 2603 (class 2606 OID 16650)
-- Name: jwt_settings jwt_settings_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2605 (class 2606 OID 16652)
-- Name: metadata metadata_active_cod_provider_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY metadata
    ADD CONSTRAINT metadata_active_cod_provider_key UNIQUE (active, cod_provider);


--
-- TOC entry 2608 (class 2606 OID 16654)
-- Name: metadata metadata_cod_metadata_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY metadata
    ADD CONSTRAINT metadata_cod_metadata_key UNIQUE (cod_metadata);


--
-- TOC entry 2611 (class 2606 OID 16656)
-- Name: metadata metadata_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY metadata
    ADD CONSTRAINT metadata_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2614 (class 2606 OID 16658)
-- Name: providers providers_cod_provider_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY providers
    ADD CONSTRAINT providers_cod_provider_key UNIQUE (cod_provider);


--
-- TOC entry 2617 (class 2606 OID 16660)
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2620 (class 2606 OID 16662)
-- Name: services services_cod_service_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_cod_service_key UNIQUE (cod_service);


--
-- TOC entry 2623 (class 2606 OID 16664)
-- Name: services services_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_pkey PRIMARY KEY ("ID");


--
-- TOC entry 2625 (class 2606 OID 19504)
-- Name: services services_relay_state_cod_provider_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_relay_state_cod_provider_key UNIQUE (relay_state, cod_provider);


--
-- TOC entry 2629 (class 2606 OID 16668)
-- Name: settings setting_cod_setting_key; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY settings
    ADD CONSTRAINT setting_cod_setting_key UNIQUE (cod_setting);


--
-- TOC entry 2631 (class 2606 OID 16670)
-- Name: settings setting_pkey; Type: CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY settings
    ADD CONSTRAINT setting_pkey PRIMARY KEY ("ID");


SET search_path = jwt, pg_catalog;

--
-- TOC entry 2557 (class 1259 OID 16671)
-- Name: fki_token_token_type_fk; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX fki_token_token_type_fk ON token USING btree (cod_type);


--
-- TOC entry 2560 (class 1259 OID 16672)
-- Name: token_header_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_header_idx ON token USING btree (header);


--
-- TOC entry 2561 (class 1259 OID 16673)
-- Name: token_payload_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_payload_idx ON token USING btree (payload);


--
-- TOC entry 2569 (class 1259 OID 16674)
-- Name: token_schemas_active_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_schemas_active_idx ON token_schemas USING btree (active);


--
-- TOC entry 2574 (class 1259 OID 16675)
-- Name: token_schemas_schema_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_schemas_schema_idx ON token_schemas USING btree (schema);


--
-- TOC entry 2575 (class 1259 OID 16676)
-- Name: token_schemas_type_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_schemas_type_idx ON token_schemas USING btree (cod_type);


--
-- TOC entry 2564 (class 1259 OID 16677)
-- Name: token_token_idx; Type: INDEX; Schema: jwt; Owner: easyspid
--

CREATE INDEX token_token_idx ON token USING btree (token);


SET search_path = saml, pg_catalog;

--
-- TOC entry 2584 (class 1259 OID 16678)
-- Name: assertions_ID_response_assertion_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX "assertions_ID_response_assertion_idx" ON assertions USING btree ("ID_response_assertion");


--
-- TOC entry 2606 (class 1259 OID 16679)
-- Name: metadata_cod_metadata_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX metadata_cod_metadata_idx ON metadata USING btree (cod_metadata bpchar_pattern_ops);


--
-- TOC entry 2609 (class 1259 OID 16680)
-- Name: metadata_cod_provider_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX metadata_cod_provider_idx ON metadata USING btree (cod_provider);


--
-- TOC entry 2612 (class 1259 OID 16681)
-- Name: providers_active_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX providers_active_idx ON providers USING btree (active);


--
-- TOC entry 2615 (class 1259 OID 16682)
-- Name: providers_name_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX providers_name_idx ON providers USING btree (name);


--
-- TOC entry 2618 (class 1259 OID 16683)
-- Name: providers_type_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX providers_type_idx ON providers USING btree (type);


--
-- TOC entry 2621 (class 1259 OID 19505)
-- Name: services_name_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX services_name_idx ON services USING btree (relay_state);


--
-- TOC entry 2626 (class 1259 OID 16685)
-- Name: setting_cod_provider_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX setting_cod_provider_idx ON settings USING btree (cod_provider DESC);


--
-- TOC entry 2627 (class 1259 OID 16686)
-- Name: setting_cod_setting_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX setting_cod_setting_idx ON settings USING btree (cod_setting DESC);


--
-- TOC entry 2597 (class 1259 OID 16687)
-- Name: signatures_fingerprint_idx; Type: INDEX; Schema: saml; Owner: easyspid
--

CREATE INDEX signatures_fingerprint_idx ON signatures USING btree (fingerprint);


SET search_path = jwt, pg_catalog;

--
-- TOC entry 2656 (class 2620 OID 16688)
-- Name: token 01_chk_token_header_insert; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "01_chk_token_header_insert" BEFORE INSERT ON token FOR EACH ROW EXECUTE PROCEDURE header_validator();


--
-- TOC entry 2664 (class 2620 OID 16689)
-- Name: token_signature 01_chk_token_header_insert; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "01_chk_token_header_insert" BEFORE INSERT ON token_signature FOR EACH ROW EXECUTE PROCEDURE header_validator();


--
-- TOC entry 2657 (class 2620 OID 16690)
-- Name: token 01_chk_token_header_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "01_chk_token_header_update" BEFORE UPDATE ON token FOR EACH ROW WHEN ((old.header IS DISTINCT FROM new.header)) EXECUTE PROCEDURE header_validator();


--
-- TOC entry 2665 (class 2620 OID 16691)
-- Name: token_signature 01_chk_token_header_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "01_chk_token_header_update" BEFORE UPDATE ON token_signature FOR EACH ROW WHEN ((old.header IS DISTINCT FROM new.header)) EXECUTE PROCEDURE header_validator();


--
-- TOC entry 2663 (class 2620 OID 16692)
-- Name: token_schemas 01_token_schemas_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "01_token_schemas_update" BEFORE UPDATE ON token_schemas FOR EACH ROW EXECUTE PROCEDURE schemas_validator();


--
-- TOC entry 2658 (class 2620 OID 16693)
-- Name: token 02_chk_token_payload_insert; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "02_chk_token_payload_insert" BEFORE INSERT ON token FOR EACH ROW EXECUTE PROCEDURE payload_validator();


--
-- TOC entry 2661 (class 2620 OID 16694)
-- Name: token_payload 02_chk_token_payload_insert; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "02_chk_token_payload_insert" BEFORE INSERT ON token_payload FOR EACH ROW EXECUTE PROCEDURE payload_validator();


--
-- TOC entry 2659 (class 2620 OID 16695)
-- Name: token 02_chk_token_payload_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "02_chk_token_payload_update" BEFORE UPDATE ON token FOR EACH ROW WHEN ((old.payload IS DISTINCT FROM new.payload)) EXECUTE PROCEDURE payload_validator();


--
-- TOC entry 2662 (class 2620 OID 16696)
-- Name: token_payload 02_chk_token_payload_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "02_chk_token_payload_update" BEFORE UPDATE ON token_payload FOR EACH ROW WHEN ((old.payload IS DISTINCT FROM new.payload)) EXECUTE PROCEDURE payload_validator();


--
-- TOC entry 2660 (class 2620 OID 18432)
-- Name: token 03_date_update; Type: TRIGGER; Schema: jwt; Owner: easyspid
--

CREATE TRIGGER "03_date_update" BEFORE UPDATE ON token FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


SET search_path = log, pg_catalog;

--
-- TOC entry 2674 (class 2620 OID 18430)
-- Name: requests 01_date_update; Type: TRIGGER; Schema: log; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON requests FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2675 (class 2620 OID 18431)
-- Name: responses 01_date_update; Type: TRIGGER; Schema: log; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON responses FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


SET search_path = saml, pg_catalog;

--
-- TOC entry 2667 (class 2620 OID 18433)
-- Name: assertions 01_date_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON assertions FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2670 (class 2620 OID 18434)
-- Name: metadata 01_date_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON metadata FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2672 (class 2620 OID 18435)
-- Name: providers 01_date_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON providers FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2673 (class 2620 OID 18436)
-- Name: settings 01_date_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON settings FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2669 (class 2620 OID 18437)
-- Name: signatures 01_date_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "01_date_update" BEFORE UPDATE ON signatures FOR EACH ROW EXECUTE PROCEDURE lib.get_current_timestamp();


--
-- TOC entry 2666 (class 2620 OID 16702)
-- Name: assertions 02_ID_assertion_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "02_ID_assertion_update" BEFORE INSERT OR UPDATE ON assertions FOR EACH ROW EXECUTE PROCEDURE assertions();


--
-- TOC entry 2668 (class 2620 OID 16703)
-- Name: signatures 02_fingerprint_update; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "02_fingerprint_update" BEFORE INSERT OR UPDATE ON signatures FOR EACH ROW EXECUTE PROCEDURE get_x509_fingerprint();


--
-- TOC entry 2671 (class 2620 OID 19151)
-- Name: metadata 02_put_cert; Type: TRIGGER; Schema: saml; Owner: easyspid
--

CREATE TRIGGER "02_put_cert" BEFORE INSERT OR UPDATE ON metadata FOR EACH ROW EXECUTE PROCEDURE getx509cert();


SET search_path = jwt, pg_catalog;

--
-- TOC entry 2641 (class 2606 OID 16704)
-- Name: token_payload token_payload_cod_type_fkey; Type: FK CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_payload
    ADD CONSTRAINT token_payload_cod_type_fkey FOREIGN KEY (cod_type) REFERENCES token_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2642 (class 2606 OID 16709)
-- Name: token_schemas token_schemas_token_type_fk; Type: FK CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_schemas
    ADD CONSTRAINT token_schemas_token_type_fk FOREIGN KEY (cod_type) REFERENCES token_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2643 (class 2606 OID 16714)
-- Name: token_signature token_signature_cod_type_fkey; Type: FK CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token_signature
    ADD CONSTRAINT token_signature_cod_type_fkey FOREIGN KEY (cod_type) REFERENCES token_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2640 (class 2606 OID 16719)
-- Name: token token_token_type_fk; Type: FK CONSTRAINT; Schema: jwt; Owner: easyspid
--

ALTER TABLE ONLY token
    ADD CONSTRAINT token_token_type_fk FOREIGN KEY (cod_type) REFERENCES token_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


SET search_path = saml, pg_catalog;

--
-- TOC entry 2644 (class 2606 OID 16724)
-- Name: assertions assertions_cod_idp_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_cod_idp_fkey FOREIGN KEY (cod_idp) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2645 (class 2606 OID 16729)
-- Name: assertions assertions_cod_sp_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_cod_sp_fkey FOREIGN KEY (cod_sp) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2646 (class 2606 OID 16734)
-- Name: assertions assertions_cod_token_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_cod_token_fkey FOREIGN KEY (cod_token) REFERENCES jwt.token(cod_token) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2647 (class 2606 OID 16739)
-- Name: assertions assertions_cod_type_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_cod_type_fkey FOREIGN KEY (cod_type) REFERENCES assertions_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2648 (class 2606 OID 16744)
-- Name: assertions assertions_providers_fk; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY assertions
    ADD CONSTRAINT assertions_providers_fk FOREIGN KEY (cod_sp) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2649 (class 2606 OID 16749)
-- Name: signatures certifcates_cod_provider_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY signatures
    ADD CONSTRAINT certifcates_cod_provider_fkey FOREIGN KEY (cod_provider) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2650 (class 2606 OID 16754)
-- Name: jwt_settings jwt_settings_cod_provider_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_cod_provider_fkey FOREIGN KEY (cod_provider) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2651 (class 2606 OID 16759)
-- Name: jwt_settings jwt_settings_cod_type_assertion_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_cod_type_assertion_fkey FOREIGN KEY (cod_type_assertion) REFERENCES assertions_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2652 (class 2606 OID 16764)
-- Name: jwt_settings jwt_settings_cod_type_token_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY jwt_settings
    ADD CONSTRAINT jwt_settings_cod_type_token_fkey FOREIGN KEY (cod_type_token) REFERENCES jwt.token_type(cod_type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2653 (class 2606 OID 16769)
-- Name: metadata metadata_cod_provider_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY metadata
    ADD CONSTRAINT metadata_cod_provider_fkey FOREIGN KEY (cod_provider) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2654 (class 2606 OID 16774)
-- Name: services services_cod_provider_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY services
    ADD CONSTRAINT services_cod_provider_fkey FOREIGN KEY (cod_provider) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2655 (class 2606 OID 16779)
-- Name: settings setting_cod_provider_fkey; Type: FK CONSTRAINT; Schema: saml; Owner: easyspid
--

ALTER TABLE ONLY settings
    ADD CONSTRAINT setting_cod_provider_fkey FOREIGN KEY (cod_provider) REFERENCES providers(cod_provider) ON UPDATE CASCADE ON DELETE RESTRICT;


-- Completed on 2017-12-07 22:59:26 CET

--
-- PostgreSQL database dump complete
--

