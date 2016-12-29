# recipe 8.12 of Ruby Cookbook http://www.oreilly.com/catalog/rubyckbk

module KeywordProcessor
  MANDATORY = :MANDATORY

  def process_params(params, defaults)
    # Reject params not presentin defaults.
    params.keys.each do |key|
      unless defaults.has_key? key
	raise ArgumentError, "No such keyword argument: #{key}"
      end
    end
    result = defaults.dup.update(params)

    # Ensure mmandatory params are given
    unfilled = result.select { |k, v| v == MANDATORY }.map { |k, v| k.inspect }
    unless unfilled.empty?
      msg = "Mandatory keywords parameters(s) nit given: #{unfilled.join(', ')}"
    end

    return result
  end
end

