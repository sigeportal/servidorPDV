unit UnitComplemento.Model;

interface
type
  TModelComplemento = class
  private
    Fcodigo: integer;
    Fquantidade: double;
  public
    property codigo: integer read Fcodigo write Fcodigo;
    property quantidade: double read Fquantidade write Fquantidade;
    class function FromJsonString(JsonString: String): TModelComplemento;
    function ToJson: String;
  end;

  TModelOpcoesNiveis = class
  private
    Fcodigo: integer;
    Fquantidade: double;
    FValorAdicional: Currency;
    FcodNivel: integer;
  public
    property codigo: integer read Fcodigo write Fcodigo;    
    property codNivel: integer read FcodNivel write FcodNivel;
    property quantidade: double read Fquantidade write Fquantidade;
    property ValorAdicional: Currency read FValorAdicional write FValorAdicional;
    class function FromJsonString(JsonString: String): TModelOpcoesNiveis;
    function ToJson: String;
  end;

implementation
uses REST.Json;

{ TModelComplemento }

class function TModelComplemento.FromJsonString(JsonString: String): TModelComplemento;
begin
  Result := TJson.JsonToObject<TModelComplemento>(JsonString);
end;

function TModelComplemento.ToJson: String;
begin
  Result := TJson.ObjectToJsonString(Self);
end;

{ TModelOpcoesNiveis }

class function TModelOpcoesNiveis.FromJsonString(JsonString: String): TModelOpcoesNiveis;
begin
	Result := TJson.JsonToObject<TModelOpcoesNiveis>(JsonString);
end;

function TModelOpcoesNiveis.ToJson: String;
begin
  Result := TJson.ObjectToJsonString(Self);
end;

end.
